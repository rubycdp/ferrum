# frozen_string_literal: true

require "singleton"

module Ferrum
  #
  # Placeholder object substituted for a JavaScript value that couldn't be
  # fully serialized because it contains circular references. It exists
  # only so that {#inspect} can report the situation instead of the
  # evaluation raising or hanging.
  #
  class CyclicObject
    include Singleton

    # Debug representation of the singleton placeholder.
    #
    # @return [String]
    def inspect
      %(#<#{self.class} JavaScript object that cannot be represented in Ruby>)
    end
  end

  class Frame
    #
    # Runs JavaScript in a frame's execution context via
    # `Runtime.callFunctionOn`, converting arguments and return values
    # between Ruby and JS, and resolving object/array/node results
    # (including cyclic ones, via {CyclicObject}) into Ruby equivalents.
    #
    # There are three entry points, all of which accept the script in the
    # same two shapes and pass arguments the same way:
    #
    # * {#evaluate} returns the value, serialized into Ruby.
    # * {#evaluate_handle} returns a {RemoteObject} that stays in the browser.
    # * {#execute} discards the value and returns `true`.
    #
    # ## Script shapes
    #
    # A script is either a bare expression, which gets wrapped in a function
    # for you, or a function declaration, which is used as-is. Use the latter
    # whenever you need more than one statement.
    #
    #   page.evaluate("window.scrollY")
    #   page.evaluate("function() { const a = 1; return a + 1 }")
    #
    # ## Arguments
    #
    # Keyword arguments become the function's parameters, in order, so the
    # script can name what it receives instead of digging through
    # `arguments[0]`:
    #
    #   page.evaluate("a + b", a: 1, b: 2)
    #
    # Each keyword is sent as its own protocol argument, so a {Node} arrives
    # in JavaScript as the live element rather than as serialized JSON.
    #
    # `timeout:` and `args:` are reserved. Pass `args:` explicitly when you
    # need a JavaScript parameter that happens to be named after one of them:
    #
    #   page.evaluate("timeout * 2", args: { timeout: 21 })
    #
    # ## Promises
    #
    # Promises are always awaited, so `async`/`await` works directly and
    # there is no separate asynchronous method:
    #
    #   page.evaluate("await fetch(url).then(r => r.text())", url: "/api")
    #
    # If the script hasn't settled within `timeout:` seconds (defaulting to
    # the page's timeout) a {ScriptTimeoutError} is raised.
    #
    module Runtime
      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f

      # Marker rejected browser-side when a script outlives its timeout.
      SCRIPT_TIMEOUT = "FERRUM_SCRIPT_TIMEOUT"

      # The same marker used by the deprecated {#evaluate_async}.
      LEGACY_SCRIPT_TIMEOUT = "timed out promise"

      # Matches a script whose whole body is a function declaration. Anything
      # trailing the closing brace means it is an expression that merely
      # starts with `function`, e.g. the IIFE `function() { ... }()`.
      FUNCTION_DECLARATION = /\A(?:async\s+)?function[\s*(]/

      # Matches an arrow declaration. Parameters are restricted to a plain
      # identifier list so that a parenthesized arrow call, `(() => 1)()`,
      # stays an expression.
      ARROW_DECLARATION = /\A(?:async\s+)?(?:
        \(\s*(?:[A-Za-z_$][\w$]*(?:\s*,\s*[A-Za-z_$][\w$]*)*\s*)?\)\s*=> |   # (a, b) =>
        [A-Za-z_$][\w$]*\s*=>                                              # a =>
      )/x

      # Trailing whitespace, semicolons and comments, which don't count as
      # content following a function's closing brace.
      TRAILING_NOISE = %r{(?:\s|;|//[^\n]*|/\*.*?\*/)*\z}m

      JS_IDENTIFIER = /\A[A-Za-z_$][A-Za-z0-9_$]*\z/

      # Reads the parameter names out of a function or arrow declaration, so
      # that named arguments can be bound by name rather than by hash order.
      PARAMETER_LISTS = [
        /\Afunction\s*\*?\s*(?:[A-Za-z_$][\w$]*)?\s*\(([^)]*)\)/m, # function foo(a, b)
        /\A\(([^)]*)\)\s*=>/m,                                     # (a, b) =>
        /\A([A-Za-z_$][\w$]*)\s*=>/ # a =>
      ].freeze

      # The public method each internal mode belongs to, for error messages.
      PUBLIC_NAMES = { value: "evaluate", handle: "evaluate_handle", none: "execute" }.freeze

      #
      # Evaluates JavaScript and returns the result, serialized into Ruby.
      #
      # @param [String] expression
      #   A JavaScript expression, or a function declaration.
      #
      # @param [Numeric, nil] timeout
      #   How long to wait for the script (and any promise it returns) to
      #   settle, in seconds. Defaults to the page timeout. `0` disables it.
      #
      # @param [Hash, nil] args
      #   Arguments to pass, when a name would collide with a reserved
      #   keyword. Takes the place of `**named`.
      #
      # @param [Hash] named
      #   Arguments to pass, becoming the function's parameters in order.
      #
      # @return [Object]
      #   The result. DOM nodes come back as {Node}, arrays and plain objects
      #   are converted recursively, and cyclic values become {CyclicObject}.
      #
      # @raise [ScriptTimeoutError]
      #   The script didn't settle within `timeout`.
      #
      # @raise [JavaScriptError]
      #   The script threw.
      #
      # @example
      #   browser.evaluate("[window.scrollX, window.scrollY]") # => [0, 0]
      #   browser.evaluate("a + b", a: 1, b: 2) # => 3
      #   browser.evaluate("await fetch(url).then(r => r.status)", url: "/") # => 200
      #
      def evaluate(expression, *positional, timeout: nil, args: nil, **named)
        run(expression, positional, (args || {}).merge(named), mode: :value, timeout: timeout)
      end

      #
      # Same as {#evaluate}, but returns a {RemoteObject} that keeps the value
      # in the browser instead of serializing it. Handles can be passed back
      # in as arguments. Primitives are returned as-is, and DOM nodes as
      # {Node}, since both are already usable from Ruby.
      #
      # @param (see #evaluate)
      #
      # @return [RemoteObject, Node, Object]
      #
      # @example
      #   list = page.evaluate_handle("document.querySelectorAll('li')")
      #   page.evaluate("Array.from(nodes).map(n => n.textContent)", nodes: list)
      #
      def evaluate_handle(expression, *positional, timeout: nil, args: nil, **named)
        run(expression, positional, (args || {}).merge(named), mode: :handle, timeout: timeout)
      end

      #
      # Runs JavaScript for its side effects and discards the result. Unlike
      # {#evaluate}, the script is used as a function body rather than an
      # expression, so multiple statements need no wrapping.
      #
      # @param (see #evaluate)
      #
      # @return [Boolean]
      #   Always `true`.
      #
      # @example
      #   browser.execute("window.scrollBy(0, 100)") # => true
      #   browser.execute(<<~JS, url: "/next")
      #     history.pushState({}, "", url);
      #     window.dispatchEvent(new Event("popstate"));
      #   JS
      #
      def execute(expression, *positional, timeout: nil, args: nil, **named)
        run(expression, positional, (args || {}).merge(named), mode: :none, timeout: timeout)
        true
      end

      #
      # @api private
      #
      # Backs {Node#evaluate}, {Node#evaluate_handle} and {Node#execute}. Runs
      # the script with `this` bound to `node`, using the same argument and
      # script conventions as {#evaluate}.
      #
      # @param [Node] node
      #   The node to bind `this` to.
      #
      # @param [Symbol] mode
      #   `:value`, `:handle` or `:none`.
      #
      # @return [Object]
      #
      def evaluate_in(node, expression, positional, args, mode: :value, timeout: nil)
        run(expression, positional, args, mode: mode, timeout: timeout, on: node)
      end

      #
      # @deprecated Use {#evaluate}, which always awaits promises. Write
      #   `page.evaluate("await thing()")` instead of passing a callback
      #   through `arguments`.
      #
      # Evaluates an asynchronous expression, appending a resolve callback as
      # the last entry of `arguments`.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Integer] wait
      #   How long to wait for the promise to settle, in seconds.
      #
      # @param [Array] args
      #   Additional arguments, reachable as `arguments[0]` and up. The
      #   resolve callback follows them.
      #
      # @return [Object]
      #
      def evaluate_async(expression, wait, *args)
        Utils::Deprecate.warn(
          "#{self.class}#evaluate_async",
          "Use #evaluate instead, which always awaits promises: " \
          "evaluate(\"await thing()\", timeout: #{wait})."
        )

        template = <<~JS
          function() {
            return new Promise((__f, __r) => {
              try {
                arguments[arguments.length] = r => __f(r);
                arguments.length = arguments.length + 1;
                setTimeout(() => __r(new Error("#{LEGACY_SCRIPT_TIMEOUT}")), %s);
                %s
              } catch(error) {
                __r(error);
              }
            });
          }
        JS

        declaration = format(template, wait * 1000, expression)
        call(declaration, args, mode: :value)
      end

      #
      # @deprecated Use {#evaluate}, which accepts a function declaration
      #   directly and names arguments with keywords. For `on:`, use
      #   {Node#evaluate}.
      #
      # Evaluates a raw JS function declaration, optionally on a specific
      # remote object instead of the frame's global execution context.
      #
      # @param [String] expression
      #   A JS function declaration, e.g. `"function(a, b) { return a + b }"`.
      #
      # @param [Array] args
      #   Arguments to pass to the function.
      #
      # @param [Node, nil] on
      #   Remote object to invoke the function on.
      #
      # @return [Object]
      #
      def evaluate_func(expression, *args, on: nil)
        Utils::Deprecate.warn(
          "#{self.class}#evaluate_func",
          "Use #evaluate, which accepts a function declaration and names arguments with keywords: " \
          "evaluate(\"function(a, b) { ... }\", a: 1, b: 2). For `on:`, use Node#evaluate."
        )

        call(expression, args, on: on, mode: :value)
      end

      #
      # @deprecated Use {Node#evaluate}.
      #
      # Evaluates an expression against a given node's remote object (+this+
      # refers to the node).
      #
      # @param [Node] node
      #   The node to evaluate the expression on.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Boolean] by_value
      #   Whether to return the plain JS value instead of resolving it.
      #
      # @param [Integer] wait
      #   Passed through to the underlying `Runtime.callFunctionOn` command.
      #
      # @return [Object]
      #
      def evaluate_on(node:, expression:, by_value: true, wait: 0)
        Utils::Deprecate.warn(
          "#{self.class}#evaluate_on",
          "Use Node#evaluate instead: node.evaluate(\"this.value\")."
        )

        declaration = format("function() { return %s }", expression)
        call(declaration, on: node, wait: wait, mode: by_value ? :raw : :value)
      end

      private

      #
      # Wraps the caller's script and hands it to {#call}. `mode` decides both
      # how the result is converted and whether the script's value is kept.
      #
      def run(expression, positional, args, mode: :value, timeout: nil, on: nil)
        params, arguments = arguments_for(expression, positional, args, mode)
        seconds = script_timeout(timeout)
        declaration = wrap_expression(expression, params, seconds, returns: mode != :none)
        # The browser-side race is what raises ScriptTimeoutError, so the
        # transport needs a longer budget than the script itself.
        call(declaration, arguments, on: on, mode: mode, timeout: [seconds + 1, @page.timeout].max)
      end

      #
      # Normalizes the two argument styles into a parameter list and a list of
      # values, warning when the deprecated positional style is used.
      #
      def arguments_for(expression, positional, args, mode)
        if positional.any?
          raise ArgumentError, "Pass arguments either positionally or by name, not both" if args.any?

          method = PUBLIC_NAMES.fetch(mode)
          Utils::Deprecate.warn(
            "#{self.class}##{method} with positional arguments",
            "Name them instead, so the script can use parameters rather than `arguments[0]`: " \
            "#{method}(\"a + b\", a: 1, b: 2)."
          )

          return [[], positional]
        end

        return [[], []] if args.empty?

        if declaration?(expression)
          # The script names its own parameters; we only supply the values,
          # ordered to match the declaration when we can read it.
          [[], ordered_values(expression, args)]
        else
          [args.keys.map { |key| validate_parameter!(key) }, args.values]
        end
      end

      #
      # Orders a hash of named arguments to match a declaration's own
      # parameter list, so that `evaluate("function(a, b) { … }", b: 2, a: 1)`
      # binds by name rather than by insertion order. Falls back to insertion
      # order when the parameters can't be read or don't line up.
      #
      def ordered_values(expression, hash)
        names = declared_parameters(expression)
        return hash.values unless names && names.sort == hash.keys.map(&:to_s).sort

        names.map { |name| hash.key?(name.to_sym) ? hash[name.to_sym] : hash[name] }
      end

      #
      # Whether the script is a complete function or arrow declaration, rather
      # than an expression that happens to begin with one.
      #
      def declaration?(expression)
        source = expression.strip
        return true if source.match?(ARROW_DECLARATION)
        return false unless source.match?(FUNCTION_DECLARATION)

        # A declaration ends at its closing brace; an IIFE has a call after it.
        source.sub(TRAILING_NOISE, "").end_with?("}")
      end

      def declared_parameters(expression)
        head = expression.strip.sub(/\Aasync\s+/, "")
        list = PARAMETER_LISTS.lazy.filter_map { |pattern| head.match(pattern)&.[](1) }.first
        return unless list

        names = list.split(",").map(&:strip).reject(&:empty?)
        names if names.all? { |name| name.match?(JS_IDENTIFIER) }
      end

      def validate_parameter!(key)
        name = key.to_s
        return name if name.match?(JS_IDENTIFIER)

        raise ArgumentError, "#{name.inspect} is not a valid JavaScript parameter name"
      end

      #
      # Builds the function declaration that is actually sent to the browser:
      # the caller's script, wrapped so that a promise it returns is raced
      # against a browser-side timeout.
      #
      def wrap_expression(expression, params, timeout, returns:)
        inner = if declaration?(expression)
                  # The declaration is spliced into an expression position, so
                  # a trailing semicolon would be a syntax error there.
                  expression.strip.sub(TRAILING_NOISE, "")
                else
                  body = if expression.strip.empty?
                           ""
                         elsif returns
                           # Parenthesized on its own lines so that neither
                           # automatic semicolon insertion nor a trailing `//`
                           # comment in the caller's expression can swallow it.
                           "return (\n#{expression.strip.sub(TRAILING_NOISE, '')}\n);"
                         else
                           expression
                         end
                  "async function(#{params.join(', ')}) {\n#{body}\n}"
                end

        return inner unless timeout.positive?

        # `inner` sits on its own lines so a trailing `//` comment in the
        # caller's script can't comment out the rest of the wrapper.
        <<~JS
          async function() {
            const __ferrum_fn = (
          #{inner}
            );
            let __ferrum_timer;
            try {
              return await Promise.race([
                Promise.resolve(__ferrum_fn.apply(this, arguments)),
                new Promise((_, reject) => {
                  __ferrum_timer = setTimeout(() => reject(new Error("#{SCRIPT_TIMEOUT}")),
                                              #{(timeout * 1000).round});
                })
              ]);
            } finally {
              clearTimeout(__ferrum_timer);
            }
          }
        JS
      end

      #
      # @param [Symbol] mode
      #   `:value` resolves the result into Ruby, `:handle` returns a
      #   {RemoteObject}, `:raw` returns the serialized JS value untouched,
      #   and `:none` discards it.
      #
      def call(declaration, arguments = [], on: nil, wait: 0, mode: :value, timeout: nil)
        # do not rescue -> retry if we operate on an existing node
        errors = on ? [] : [NodeNotFoundError, NoExecutionContextError]

        Utils::Attempt.with_retry(errors: errors, max: INTERMITTENT_ATTEMPTS, wait: INTERMITTENT_SLEEP) do
          target = if on
                     response = @page.command("DOM.resolveNode", nodeId: on.node_id)
                     { objectId: response.dig("object", "objectId") }
                   else
                     { executionContextId: execution_id! }
                   end
          target[:returnByValue] = true if %i[raw none].include?(mode)

          response = @page.command("Runtime.callFunctionOn",
                                   wait: wait, timeout: timeout, slowmoable: true,
                                   awaitPromise: true,
                                   functionDeclaration: declaration,
                                   arguments: prepare_args(arguments),
                                   **target)
          handle_error(response)

          result = response["result"]

          case mode
          when :none then nil
          when :raw then result["value"]
          when :handle then handle_remote_object(result)
          else handle_response(result)
          end
        end
      end

      def script_timeout(timeout)
        (timeout || @page.timeout).to_f
      end

      # FIXME: We should have a central place to handle all type of errors
      def handle_error(response)
        result = response["result"]
        details = response["exceptionDetails"]
        return if details.nil? && result["subtype"] != "error"

        description = result["description"] ||
                      details&.dig("exception", "description") ||
                      details&.dig("exception", "value") ||
                      details&.fetch("text", nil)

        raise ScriptTimeoutError if description.to_s.include?(SCRIPT_TIMEOUT) ||
                                    description.to_s.include?(LEGACY_SCRIPT_TIMEOUT)

        raise JavaScriptError, details || { "text" => description }
      end

      # Primitives and DOM nodes are already usable from Ruby, so only genuine
      # browser-side objects are handed back as a {RemoteObject}.
      def handle_remote_object(result)
        return handle_response(result) if result["objectId"].nil? || result["subtype"] == "node"

        RemoteObject.new(@page, result)
      end

      def handle_response(response, check_cyclic: true)
        case response["type"]
        when "boolean", "number", "string"
          response["value"]
        when "undefined"
          nil
        when "function"
          {}
        when "object"
          object_id = response["objectId"]

          case response["subtype"]
          when "node"
            description = @page.command("DOM.describeNode", objectId: object_id)["node"]
            Node.new(self, @page.target_id, description, object_id: object_id)
          when "array"
            reduce_props(object_id, [], check_cyclic: check_cyclic) do |memo, key, value|
              next(memo) unless Integer(key, exception: false)

              value = value["objectId"] ? handle_response(value, check_cyclic: false) : value["value"]
              memo.insert(key.to_i, value)
            end.compact
          when "date"
            response["description"]
          when "null"
            nil
          else
            reduce_props(object_id, {}, check_cyclic: check_cyclic) do |memo, key, value|
              value = value["objectId"] ? handle_response(value, check_cyclic: false) : value["value"]
              memo.merge(key => value)
            end
          end
        end
      end

      def prepare_args(args)
        args.map do |arg|
          case arg
          when Node
            resolved = @page.command("DOM.resolveNode", nodeId: arg.node_id)
            { objectId: resolved["object"]["objectId"] }
          when RemoteObject
            { objectId: arg.remote_id }
          when Hash
            arg["objectId"] ? { objectId: arg["objectId"] } : { value: arg }
          else
            { value: arg }
          end
        end
      end

      def reduce_props(object_id, to, check_cyclic: true)
        if check_cyclic && cyclic?(object_id).dig("result", "value")
          to.is_a?(Array) ? [cyclic_object] : cyclic_object
        else
          props = @page.command("Runtime.getProperties", ownProperties: true, objectId: object_id)
          props["result"].reduce(to) do |memo, prop|
            next(memo) unless prop["enumerable"]

            yield(memo, prop["name"], prop["value"])
          end
        end
      end

      def cyclic?(object_id)
        @page.command(
          "Runtime.callFunctionOn",
          objectId: object_id,
          returnByValue: true,
          functionDeclaration: <<~JS
            function() {
              if (Array.isArray(this) &&
                  this.every(e => e instanceof Node)) {
                return false;
              }

              function detectCycle(obj, seen) {
                if (typeof obj === "object") {
                  if (seen.indexOf(obj) !== -1) {
                    return true;
                  }
                  for (let key in obj) {
                    if (obj.hasOwnProperty(key) && detectCycle(obj[key], seen.concat([obj]))) {
                      return true;
                    }
                  }
                }

                return false;
              }

              return detectCycle(this, []);
            }
          JS
        )
      end

      def cyclic_object
        CyclicObject.instance
      end
    end
  end
end

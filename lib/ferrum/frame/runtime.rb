# frozen_string_literal: true

require "singleton"
require "ferrum/frame/script"

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
    # Arrow functions keep the `this` of where they're defined, so on a
    # {Node} use a `function` declaration when the script needs `this`.
    #
    # ## Arguments
    #
    # Keyword arguments become the function's parameters, so the script can
    # name what it receives instead of digging through `arguments[0]`:
    #
    #   page.evaluate("a + b", a: 1, b: 2)
    #
    # Each keyword is sent as its own protocol argument, so a {Node} arrives
    # in JavaScript as the live element rather than as serialized JSON. When
    # the script is a function declaration, arguments bind to its parameters
    # by name, and one it doesn't declare raises an `ArgumentError`.
    #
    # Positional arguments still work and land in `arguments[0]` and up, but
    # can't be mixed with keyword ones.
    #
    # `timeout:` and `args:` are reserved. Pass `args:` explicitly when you
    # need a JavaScript parameter that happens to be named after one of them:
    #
    #   page.evaluate("timeout * 2", args: { timeout: 21 })
    #
    # ## Promises
    #
    # A returned promise, or any object with a `then` method, is awaited, so
    # `async`/`await` works directly and there is no separate asynchronous
    # method:
    #
    #   page.evaluate("await fetch(url).then(r => r.text())", url: "/api")
    #
    # If the script hasn't settled within `timeout:` seconds (defaulting to
    # the page's timeout) a {ScriptTimeoutError} is raised. `timeout: 0` lets
    # it run for as long as it takes.
    #
    module Runtime
      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f

      # Stands in for a declared parameter the caller didn't pass, which CDP
      # sends as `undefined`.
      UNDEFINED = Object.new.freeze
      private_constant :UNDEFINED

      #
      # Evaluates JavaScript and returns the result, serialized into Ruby.
      #
      # @param [String] expression
      #   A JavaScript expression, or a function declaration.
      #
      # @param [Array] positional
      #   Arguments reachable as `arguments[0]` and up. Can't be combined
      #   with named ones.
      #
      # @param [Hash] keywords
      #   Named arguments, which become the function's parameters, plus:
      #
      # @option keywords [Numeric, nil] :timeout
      #   How long to wait for the script, and any promise it returns, to
      #   settle, in seconds. Defaults to the page timeout. `0` disables it.
      #
      # @option keywords [Hash] :args
      #   Named arguments whose names would collide with `timeout` or `args`.
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
      def evaluate(expression, *positional, **keywords)
        run(expression, positional, keywords, mode: :value)
      end

      #
      # Same as {#evaluate}, but returns a {RemoteObject} that keeps the value
      # in the browser instead of serializing it. Handles can be passed back
      # in as arguments. Primitives are returned as-is, and DOM nodes as
      # {Node}, since both are already usable from Ruby.
      #
      # @param (see #evaluate)
      # @option (see #evaluate)
      #
      # @return [RemoteObject, Node, Object]
      #
      # @example
      #   list = page.evaluate_handle("document.querySelectorAll('li')")
      #   page.evaluate("Array.from(nodes).map(n => n.textContent)", nodes: list)
      #
      def evaluate_handle(expression, *positional, **keywords)
        run(expression, positional, keywords, mode: :handle)
      end

      #
      # Runs JavaScript for its side effects and discards the result. Unlike
      # {#evaluate}, the script is used as a function body rather than an
      # expression, so multiple statements need no wrapping.
      #
      # @param (see #evaluate)
      # @option (see #evaluate)
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
      def execute(expression, *positional, **keywords)
        run(expression, positional, keywords, mode: :none)
        true
      end

      #
      # @api private
      #
      # Backs {Node#evaluate}, {Node#evaluate_handle}, {Node#execute} and
      # {RemoteObject#value}. Runs the script with `this` bound to `object`,
      # using the same argument and script conventions as {#evaluate}.
      #
      # @param [Node, RemoteObject] object
      #   The node or object to bind `this` to.
      #
      # @param [Symbol] mode
      #   `:value`, `:handle` or `:none`.
      #
      # @return [Object]
      #
      def evaluate_in(object, expression, positional, keywords, mode: :value)
        run(expression, positional, keywords, mode: mode, on: object)
      end

      private

      #
      # Wraps the caller's script and hands it to {#call}. `mode` decides both
      # how the result is converted and whether the script's value is kept.
      #
      def run(expression, positional, keywords, mode:, on: nil)
        script = Script.new(expression)
        named = keywords.except(:timeout, :args)
        params, values = arguments_for(script, positional, named_arguments(keywords[:args], named), mode)
        call(wrap(script, params, mode), values, on: on, mode: mode, timeout: script_timeout(keywords[:timeout]))
      end

      #
      # Normalizes the two argument styles into a parameter list and a list of
      # values.
      #
      def arguments_for(script, positional, named, mode)
        if positional.any?
          raise ArgumentError, "Pass arguments either positionally or by name, not both" if named.any?

          return [[], positional]
        end

        return [[], []] if named.empty?
        return [[], bind_to_parameters(script, named)] if function?(script, mode)

        [named.keys.map { |key| validate_parameter!(key) }, named.values]
      end

      def named_arguments(args, named)
        return named if args.nil?
        raise ArgumentError, "args: takes a Hash of named arguments, got #{args.class}" unless args.is_a?(Hash)

        args.merge(named)
      end

      #
      # Orders named arguments to match a declaration's own parameter list, so
      # that `evaluate("function(a, b) { … }", b: 2, a: 1)` binds by name.
      # Parameters left out are passed as `undefined`. Falls back to insertion
      # order when the parameters can't be read, e.g. when destructured.
      #
      def bind_to_parameters(script, named)
        names = script.parameters
        return named.values unless names

        values = named.transform_keys(&:to_s)
        unknown = values.keys - names
        if unknown.any?
          raise ArgumentError, "#{unknown.map(&:inspect).join(', ')} not declared by the function, " \
                               "which takes (#{names.join(', ')})"
        end

        last = names.rindex { |name| values.key?(name) }
        names.take(last.to_i + 1).map { |name| values.fetch(name, UNDEFINED) }
      end

      def validate_parameter!(key)
        name = key.to_s
        return name if name.match?(Script::JS_IDENTIFIER) && !Script::RESERVED_WORDS.include?(name)

        raise ArgumentError, "#{name.inspect} is not a valid JavaScript parameter name"
      end

      # A named function in a function body is a statement defining it, so
      # {#execute} runs it as a body rather than calling it.
      def function?(script, mode)
        script.declaration? && !(mode == :none && script.named_function?)
      end

      #
      # Builds the function declaration that is actually sent to the browser:
      # the caller's declaration as-is, or an expression wrapped in one.
      #
      def wrap(script, params, mode)
        return script.code if function?(script, mode)

        # Parenthesized on its own lines so that neither automatic semicolon
        # insertion nor a trailing `//` comment in the caller's expression can
        # swallow it.
        body = mode == :none || script.code.empty? ? script.code : "return (\n#{script.code}\n);"
        "#{'async ' if script.awaits?}function(#{params.join(', ')}) {\n#{body}\n}"
      end

      # Waiting for the response is what bounds the script, so a page that
      # replaces `Promise` or `setTimeout`, or throttles timers, can't defeat
      # it.
      def script_timeout(timeout)
        seconds = (timeout || @page.timeout).to_f
        seconds.positive? ? seconds : Float::INFINITY
      end

      #
      # @param [Symbol] mode
      #   `:value` resolves the result into Ruby, `:handle` returns a
      #   {RemoteObject}, and `:none` discards it.
      #
      def call(declaration, values, on:, mode:, timeout:)
        # do not rescue -> retry if we operate on an existing node
        errors = on ? [] : [NodeNotFoundError, NoExecutionContextError]

        Utils::Attempt.with_retry(errors: errors, max: INTERMITTENT_ATTEMPTS, wait: INTERMITTENT_SLEEP) do
          target = call_target(on)
          target[:returnByValue] = true if mode == :none

          response = call_function(declaration, values, target, timeout)
          handle_error(response)

          result = response["result"]
          case mode
          when :none then nil
          when :handle then handle_remote_object(result)
          else handle_response(result)
          end
        end
      end

      def call_function(declaration, values, target, timeout)
        @page.command("Runtime.callFunctionOn",
                      timeout: timeout, slowmoable: true, awaitPromise: true,
                      functionDeclaration: declaration, arguments: prepare_args(values), **target)
      rescue TimeoutError
        raise ScriptTimeoutError
      end

      def call_target(on)
        if on.is_a?(RemoteObject)
          { objectId: on.remote_id }
        elsif on
          { objectId: resolve_node(on) }
        else
          { executionContextId: execution_id! }
        end
      end

      # A returned `Error` raises too, as it does when thrown.
      def handle_error(response)
        result = response["result"]
        details = response["exceptionDetails"]
        return if details.nil? && result["subtype"] != "error"

        raise JavaScriptError, details || { "exception" => result }
      end

      def handle_remote_object(result)
        return handle_response(result) if result["objectId"].nil? || result["subtype"] == "node"

        RemoteObject.new(self, @page, result)
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

      def resolve_node(node)
        @page.command("DOM.resolveNode", nodeId: node.node_id, **resolve_node_options).dig("object", "objectId")
      end

      def resolve_node_options
        {}
      end

      def prepare_args(args)
        args.map do |arg|
          case arg
          when Node
            { objectId: resolve_node(arg) }
          when RemoteObject
            { objectId: arg.remote_id }
          when UNDEFINED
            {}
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

# frozen_string_literal: true

require "singleton"
require "ferrum/frame/script"
require "ferrum/frame/runtime/legacy"

module Ferrum
  #
  # Placeholder substituted for a reference back to a JavaScript object that
  # contains it, e.g. `a.self = a`, so that the result stays a finite Ruby
  # Hash or Array.
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
    # between Ruby and JS, and resolving object/array/node results into Ruby
    # equivalents. A reference back to an enclosing object becomes
    # {CyclicObject}.
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
    # A script is either code that gets wrapped in a function for you and
    # returns the value of its last statement, or a function declaration,
    # which is used as-is.
    #
    #   page.evaluate("window.scrollY")
    #   page.evaluate("const a = 1\na + 1")
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
    # in JavaScript as the live element rather than as serialized JSON.
    #
    # A function declaration names its parameters itself, so it takes
    # positional arguments, in the order it declares them:
    #
    #   page.evaluate("function(a, b) { return a + b }", 1, 2)
    #
    # Positional arguments also work with an expression, landing in
    # `arguments[0]` and up, but can't be mixed with keyword ones.
    #
    # `timeout:` is reserved for Ferrum, so a variable of the script can't
    # take that name.
    #
    # ## Promises
    #
    # A returned promise, or any object with a `then` method, is awaited, so
    # `async`/`await` works directly and there is no separate asynchronous
    # method:
    #
    #   page.evaluate("await fetch(url).then(r => r.text())", url: "/api")
    #
    # ## Timeouts
    #
    # If the script hasn't settled within `timeout:` seconds (defaulting to
    # the page's timeout) a {ScriptTimeoutError} is raised.
    #
    # The timeout is how long Ruby waits for Chrome's answer, so a page that
    # replaces `Promise` or `setTimeout` can't defeat it, but it doesn't stop
    # the script. A promise that never settles is harmless, while a
    # synchronous endless loop keeps the page's JavaScript busy, so later
    # calls on that page time out too. Other pages aren't affected.
    #
    # ## How a call runs
    #
    # All three methods, and their {Node} counterparts through
    # {#evaluate_in}, take the same steps and differ only in a mode:
    # `:value`, `:handle` or `:none`.
    #
    # 1. **Parse.** {Script} reads the source once, skipping strings,
    #    template literals, regular expressions and comments. It finds the
    #    code without surrounding comments and semicolons, whether it's a
    #    function or arrow declaration, where its last statement starts, and
    #    whether it uses `await`.
    # 2. **Arguments.** `timeout:` is taken out of the keywords.
    #    Positional arguments are passed as they are. Named ones become the
    #    parameters of the function an expression is wrapped in, and raise
    #    for a declaration, which names its parameters itself.
    # 3. **Wrap.** A declaration is sent as it is. An expression becomes
    #    `function(<names>) { return (<code>) }`, `async` when it uses
    #    `await`. Of several statements, only the last is returned, as in
    #    `function() { a(); return (b) }`. {#execute} uses the script as
    #    written as the function body instead.
    # 4. **Call.** One `Runtime.callFunctionOn` in the frame's context, or
    #    with `this` bound to a node or remote object. When it returns a
    #    promise or a plain object, a second call awaits it, which isn't
    #    retried after a navigation, as the script has already run. {Node}
    #    and {RemoteObject} arguments are passed by reference.
    # 5. **Result.** {#evaluate} converts Chrome's deep serialization into
    #    Ruby, {#evaluate_handle} wraps an object in a {RemoteObject}, and
    #    {#execute} returns `true`. A thrown value raises {JavaScriptError}.
    #
    # For example, this call:
    #
    #   page.evaluate("await fetch(url).then(r => r.status)", url: "/ping")
    #
    # is an expression that uses `await`, so it's sent as:
    #
    #   async function(url) {
    #   return (
    #   await fetch(url).then(r => r.status)
    #   );
    #   }
    #
    # with the arguments `[{ value: "/ping" }]`. Chrome answers with a
    # promise, a second call awaits it and gets
    # `{ type: "number", value: 200 }`, which comes back as
    # `200`. A declaration takes positional arguments instead:
    #
    #   node.evaluate("function(prefix, suffix) { return prefix + this.id + suffix }", "#", "!")
    #
    # is sent unchanged, with `this` bound to the node and the arguments
    # `["#", "!"]`, and comes back as `"#main!"`.
    #
    # ## Scripts written for the old API
    #
    # Until Ferrum 0.21, a call that only the old API could have made runs
    # the old way through {Legacy} and warns when its result will change.
    # That's a call without named arguments, or one whose script reads
    # `arguments` or also passes positional ones, unless the script is a
    # declaration or uses `await`, or the method is {#evaluate_handle} or
    # {Node#execute}.
    # `FERRUM_JS_API=new` sends every call through the steps above.
    #
    module Runtime
      include Legacy

      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f
      DEEP_SERIALIZATION = {
        serialization: "deep",
        additionalParameters: { maxNodeDepth: 0, includeShadowTree: "none" }
      }.freeze
      # Describes a primitive or node result, which a handle can't stand for,
      # without serializing an object that stays in the browser.
      SHALLOW_SERIALIZATION = DEEP_SERIALIZATION.merge(maxDepth: 0).freeze
      UNSERIALIZABLE_NUMBERS = {
        "NaN" => Float::NAN,
        "-0" => -0.0,
        "Infinity" => Float::INFINITY,
        "-Infinity" => -Float::INFINITY
      }.freeze

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
      #   settle, in seconds. Defaults to the page timeout.
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
      # Parses the script, turns the arguments into a parameter list and
      # values, wraps the script into the function declaration that's sent,
      # and hands it to {#call}. `mode` decides both how the result is
      # converted and whether the script's value is kept.
      #
      def run(expression, positional, keywords, mode:, on: nil)
        script = Script.new(expression)
        if legacy?(script, positional, keywords, mode: mode, on: on)
          return run_legacy(script, positional, keywords, mode: mode, on: on)
        end

        named = keywords.except(:timeout)
        params, values = arguments_for(script, positional, named)
        call(wrap(script, params, mode), values, on: on, mode: mode, timeout: script_timeout(keywords[:timeout]))
      end

      #
      # Normalizes the two argument styles into the parameter names of the
      # wrapping function and the values to send:
      #
      # * positional ones: no names, values reachable as `arguments[0]` and up,
      #   or as a declaration's own parameters;
      # * named ones for an expression: their names and their values. A
      #   declaration names its parameters itself, so it takes positional
      #   ones only.
      #
      def arguments_for(script, positional, named)
        if positional.any?
          raise ArgumentError, "Pass arguments either positionally or by name, not both" if named.any?

          return [[], positional]
        end

        return [[], []] if named.empty?
        if script.declaration?
          raise ArgumentError, "A function declaration names its own parameters, so pass its arguments " \
                               "positionally: evaluate(\"function(a, b) { … }\", 1, 2)"
        end

        [named.keys.map(&:to_s), named.values]
      end

      #
      # Builds the function declaration that is actually sent to the browser:
      # the caller's declaration as-is, or an expression wrapped in one.
      #
      #   wrap(Script.new("a + b"), %w[a b], :value)
      #   # => "function(a, b) { return (a + b\n);\n}"
      #   wrap(Script.new("await x()"), [], :none)
      #   # => "async function() { await x()\n}"
      #
      def wrap(script, params, mode)
        return script.code if script.declaration?

        # A body keeps its trailing semicolons, which can be statements of
        # their own, as in `while (busy());`. Otherwise the last statement is
        # returned, parenthesized so that automatic semicolon insertion can't
        # end the `return`. The script starts on the first line, so that error
        # locations match its lines.
        head, last = script.split_last_statement
        body = if mode == :none then script.source
               elsif last.empty? then ""
               elsif last.match?(Script::STATEMENT) then script.code
               else "#{head}return (#{last}\n);"
               end
        "#{'async ' if script.awaits?}function(#{params.join(', ')}) { #{body}\n}"
      end

      # Waiting for the response is what bounds the script, so a page that
      # replaces `Promise` or `setTimeout`, or throttles timers, can't defeat
      # it.
      def script_timeout(timeout)
        (timeout || @page.timeout).to_f
      end

      #
      # Sends the declaration with `Runtime.callFunctionOn`, retrying while
      # the frame's context is being replaced unless `this` is bound to an
      # existing node, and converts the result.
      #
      # @param [Symbol] mode
      #   `:value` resolves the result into Ruby, `:handle` returns a
      #   {RemoteObject}, and `:none` discards it.
      #
      def call(declaration, values, on:, mode:, timeout:)
        # do not rescue -> retry if we operate on an existing node
        errors = on ? [] : [NodeNotFoundError, NoExecutionContextError]

        serialization = mode == :value ? DEEP_SERIALIZATION : SHALLOW_SERIALIZATION
        response = Utils::Attempt.with_retry(errors: errors, max: INTERMITTENT_ATTEMPTS, wait: INTERMITTENT_SLEEP) do
          call_function(declaration, values, call_target(on), serialization, timeout)
        end
        handle_error(response, declaration)

        result = response["result"]
        result = await_promise(result, serialization, timeout) if thenable?(result)
        case mode
        when :none then nil
        when :handle then handle_remote_object(result)
        else handle_response(result)
        end
      end

      def call_function(declaration, values, target, serialization, timeout)
        @page.command("Runtime.callFunctionOn",
                      timeout: timeout, slowmoable: true, serializationOptions: serialization,
                      functionDeclaration: declaration, arguments: prepare_args(values), **target)
      rescue TimeoutError
        raise ScriptTimeoutError
      end

      # A promise, or a plain object that may be one, such as the promises of
      # zone.js or Bluebird, which Chrome doesn't report as `promise`.
      def thenable?(result)
        result["type"] == "object" && [nil, "promise"].include?(result["subtype"])
      end

      # Awaited outside the retries: by now the script has run, and running
      # it again after a navigation would repeat what it did. Awaiting an
      # object that isn't thenable returns it as it is.
      def await_promise(promise, serialization, timeout)
        response = @page.command("Runtime.callFunctionOn",
                                 timeout: timeout, awaitPromise: true, serializationOptions: serialization,
                                 functionDeclaration: "function() { return this }", objectId: promise["objectId"])
        handle_error(response)
        response["result"]
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

      # Chrome reports no location for a script that doesn't compile, so the
      # function it compiled is added, wrapper included.
      def handle_error(response, declaration = nil)
        details = response["exceptionDetails"]
        return unless details

        if declaration && details["stackTrace"].nil? && details.dig("exception", "className") == "SyntaxError"
          description = "#{details.dig('exception', 'description')}\n  in: #{declaration[0, 500]}"
          details = details.merge("exception" => details["exception"].merge("description" => description))
        end
        raise JavaScriptError, details
      end

      def handle_remote_object(result)
        return RemoteObject.new(self, @page, result) if result["objectId"] && result["subtype"] != "node"

        handle_response(result)
      end

      def handle_response(response)
        deserialize(response["deepSerializedValue"])
      end

      # Chrome sends a shared object in full once and refers to it after
      # that, so each one is converted once and reused, as the same object.
      def deserialize(serialized, references = {}, path = [], converted = {})
        reference = serialized["weakLocalObjectReference"]
        if reference
          return cyclic_object if path.include?(reference)
          return converted[reference] if converted.key?(reference)

          serialized = references[reference] ||= serialized
          path += [reference]
        end

        result = convert(serialized, references, path, converted)
        converted[reference] = result if reference
        result
      end

      def convert(serialized, references, path, converted)
        value = serialized["value"]
        case serialized["type"]
        when "undefined", "null", "symbol"
          nil
        when "boolean", "string", "date"
          value
        when "number"
          UNSERIALIZABLE_NUMBERS.fetch(value, value)
        when "bigint"
          Integer(value)
        when "array", "nodelist", "htmlcollection"
          value.map { |v| deserialize(v, references, path, converted) }
        when "object"
          value.to_h { |k, v| [k, deserialize(v, references, path, converted)] }
        when "node"
          Node.new(self, value)
        else
          {}
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
          if nested_reference?(arg)
            raise ArgumentError, "A Ferrum::Node or Ferrum::RemoteObject inside an Array or Hash can't be passed " \
                                 "to JavaScript. Pass each one as its own argument"
          end

          case arg
          when Node
            { objectId: resolve_node(arg) }
          when RemoteObject
            { objectId: arg.remote_id }
          when Hash
            arg["objectId"] ? { objectId: arg["objectId"] } : { value: arg }
          else
            { value: arg }
          end
        end
      end

      # A protocol argument is either a value or a reference, so a node in
      # an array or hash would only arrive as its `to_s`.
      def nested_reference?(value)
        children = case value
                   when Array then value
                   when Hash then value.values
                   else return false
                   end
        children.any? { |v| v.is_a?(Node) || v.is_a?(RemoteObject) || nested_reference?(v) }
      end

      def cyclic_object
        CyclicObject.instance
      end
    end
  end
end

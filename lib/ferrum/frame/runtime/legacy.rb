# frozen_string_literal: true

module Ferrum
  class Frame
    module Runtime
      #
      # The JavaScript evaluation API as it was before named arguments, kept
      # so that scripts written for it return exactly what they used to. A
      # call takes this path unless `FERRUM_JS_API=new` is set or the call
      # uses something only the new API has: named arguments, a function
      # declaration, `await`, or one of the new methods.
      #
      # Whatever runs here is checked for what Ferrum 0.21 will do
      # differently, which is warned about with a suggested rewrite. 0.21
      # removes this module, leaving only the new way.
      #
      # The script is parsed by {Script} as for the new way, to route the
      # call and to spot what changes. An old-style call then runs as it did
      # in Ferrum 0.19:
      #
      # 1. **Arguments.** Keyword arguments, `timeout:` included, are
      #    appended to the positional ones as one trailing object.
      # 2. **Wrap.** The source is wrapped as it is, in
      #    `function() { return <source> }`, or `function() { <source> }` for
      #    {#execute}. A line break after `return` ends that statement, and
      #    only the first statement of `"a(); b"` runs.
      # 3. **Call.** One `Runtime.callFunctionOn` that doesn't await
      #    promises, bounded by the page timeout, which raises a plain
      #    {TimeoutError}. {#evaluate_async} races the promise against a
      #    timer in the page instead.
      # 4. **Check.** Before the result is converted, it's compared with what
      #    0.21 will do: its subtype for promises, nodes and dates, its
      #    properties for nodes in an array, and the parsed script for
      #    statements separated by a semicolon. Nothing is
      #    run on the result, so getters and proxy traps don't fire.
      # 5. **Warn.** Each difference warns once per call site, naming the
      #    first caller outside installed gems, then the result is converted
      #    as before: a promise comes back as `{}`.
      #
      module Legacy
        # Marker rejected browser-side by {#evaluate_async} when it times out.
        TIMEOUT_MARKER = "timed out promise"

        NEXT_VERSION = "Ferrum 0.21"

        #
        # @deprecated Will be removed in Ferrum 0.21. Use {#evaluate}, which awaits
        #   promises: `page.evaluate("await thing()", timeout: wait)`.
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
            "#{self.class}#evaluate_async will be removed in Ferrum 0.21. Use #evaluate, which waits for a " \
            "returned promise, instead of calling the last of `arguments`: " \
            "evaluate(\"await new Promise(resolve => setTimeout(resolve, 100))\", timeout: #{wait})."
          )

          template = <<~JS
            function() {
              return new Promise((__f, __r) => {
                try {
                  arguments[arguments.length] = r => __f(r);
                  arguments.length = arguments.length + 1;
                  setTimeout(() => __r(new Error("#{TIMEOUT_MARKER}")), %s);
                  %s
                } catch(error) {
                  __r(error);
                }
              });
            }
          JS

          expression = format(template, wait * 1000, expression)
          legacy_call(expression: expression, arguments: args, awaitPromise: true)
        end

        #
        # @deprecated Will be removed in Ferrum 0.21. Use {#evaluate}, which takes a
        #   function declaration and named arguments, or {Node#evaluate}.
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
            "#{self.class}#evaluate_func will be removed in Ferrum 0.21. Use #evaluate, which takes a function " \
            "declaration: evaluate(\"function(a, b) { return a + b }\", 1, 2). " \
            "For on:, use node.evaluate."
          )

          legacy_call(expression: expression, arguments: args, on: on)
        end

        #
        # @deprecated Will be removed in Ferrum 0.21. Use {Node#evaluate}.
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
          replacement = 'node.evaluate("this.value")'
          replacement = "page.wait_for_navigation!(#{wait}) { #{replacement} }" if wait.positive?
          Utils::Deprecate.warn("#{self.class}#evaluate_on will be removed in Ferrum 0.21. Use #{replacement} instead.")

          options = { handle: true }
          expression = format("function() { return %s }", expression)
          options = { handle: false, returnByValue: true } if by_value
          legacy_call(expression: expression, on: node, wait: wait, **options)
        end

        private

        # Calls that only the new API could have made go the new way.
        def legacy?(script, positional, keywords, mode:, on:)
          return false if ENV.fetch("FERRUM_JS_API", nil) == "new"
          return false if mode == :handle || (on && (mode == :none || !on.is_a?(Node)))
          return false if script.declaration? || script.awaits?

          keywords.empty? || positional.any? || script.uses?("arguments")
        end

        # Keywords used to be collected into a trailing Hash, `timeout:`
        # included, so they're passed on exactly that way.
        def run_legacy(script, positional, keywords, mode:, on:)
          warn_about_keywords(script, positional, keywords)
          arguments = keywords.empty? ? positional : [*positional, keywords]

          if mode == :none
            legacy_execute(script, arguments)
          elsif on
            legacy_evaluate_on(script, arguments, on)
          else
            legacy_evaluate(script, arguments)
          end
        end

        def legacy_evaluate(script, arguments)
          warn_about_line_break(script)
          response = legacy_call(expression: format("function() { return %s }", script.source),
                                 arguments: arguments, handle: :raw, serializationOptions: DEEP_SERIALIZATION)
          legacy_handle_error(response)
          warn_about_result(script, response, :value)
          warn_about_statements(script)
          handle_response(response["result"])
        end

        def legacy_evaluate_on(script, arguments, node)
          warn_about_line_break(script)
          response = legacy_call(expression: format("function() { return %s }", script.source),
                                 arguments: arguments, on: node, handle: :raw)
          legacy_handle_error(response)
          warn_about_result(script, response, :node)
          warn_about_statements(script)
          serialize(response["result"])
        end

        def legacy_execute(script, arguments)
          response = legacy_call(expression: format("function() { %s }", script.source),
                                 arguments: arguments, handle: :raw)
          legacy_handle_error(response)
          warn_about_result(script, response, :none)
          release(response["result"])
          true
        end

        # What `returnByValue` used to give, fetched afterwards so that the
        # result could be inspected first.
        def serialize(result)
          object_id = result["objectId"]
          return result["value"] unless object_id

          response = @page.command("Runtime.callFunctionOn", objectId: object_id, returnByValue: true,
                                                             functionDeclaration: "function() { return this }")
          response.dig("result", "value")
        ensure
          release(result)
        end

        def release(result)
          object_id = result&.dig("objectId")
          @page.command("Runtime.releaseObject", objectId: object_id) if object_id
        rescue BrowserError
          nil
        end

        def legacy_call(expression:, arguments: [], on: nil, wait: 0, handle: true, **options)
          # do not rescue -> retry if we operate on an existing node
          errors = on ? [] : [NodeNotFoundError, NoExecutionContextError]

          Utils::Attempt.with_retry(errors: errors, max: INTERMITTENT_ATTEMPTS, wait: INTERMITTENT_SLEEP) do
            params = options.dup

            params = params.merge(objectId: resolve_node(on)) if on
            params = params.merge(serializationOptions: DEEP_SERIALIZATION) if handle == true

            if params[:executionContextId].nil? && params[:objectId].nil?
              params = params.merge(executionContextId: execution_id!)
            end

            response = @page.command("Runtime.callFunctionOn",
                                     wait: wait, slowmoable: true,
                                     **params.merge(functionDeclaration: expression,
                                                    arguments: prepare_args(arguments)))
            next response if handle == :raw

            legacy_handle_error(response)
            response = response["result"]

            handle ? handle_response(response) : response["value"]
          end
        end

        def legacy_handle_error(response)
          details = response["exceptionDetails"]
          return unless details

          description = details.dig("exception", "description").to_s
          raise ScriptTimeoutError if description.start_with?("Error: #{TIMEOUT_MARKER}")

          raise JavaScriptError, details
        end

        def warn_about_keywords(script, positional, keywords)
          return if keywords.empty?

          if positional.any?
            warn_about(script, "Mixing positional and keyword arguments will raise ArgumentError in #{NEXT_VERSION}, " \
                               "where keywords will become named parameters instead of a trailing object. Pass the " \
                               "object in braces, evaluate(\"…\", 1, { foo: 1 }), or name every argument.")
          else
            warn_about(script, "Keyword arguments will become named parameters in #{NEXT_VERSION} instead of " \
                               "arriving as one object in `arguments[0]`. Name the object instead: " \
                               "evaluate(\"options.foo\", options: { foo: 1 }).")
          end
        end

        def warn_about_line_break(script)
          return unless script.leading_line_break?

          warn_about(script, "This script never runs: the line break before it ends the `return` it's placed " \
                             "after, so the result is always nil. #{NEXT_VERSION} will run it and return its value. " \
                             "Check it's safe to run, or remove it.")
        end

        def warn_about_statements(script)
          return if script.leading_line_break? || !script.several_statements?

          warn_about(script, "This script is more than one statement, and today only the first one runs. " \
                             "#{NEXT_VERSION} will run them all and return the value of the last one. Check the " \
                             "rest is safe to run, or remove it.")
        end

        def warn_about_result(script, response, kind)
          result = response["result"]
          case result["subtype"]
          when "promise" then warn_about_promise(script, kind)
          when "node" then warn_about_node(script, "a DOM node", "Ferrum::Node") if kind == :node
          when "date" then warn_about_node(script, "a Date", "its ISO 8601 string") if kind == :node
          when "array" then warn_about_nodes(script, result) if kind == :node
          end
        end

        def warn_about_promise(script, kind)
          if kind == :none
            warn_about(script, "This script returns a promise, which #execute will wait for in #{NEXT_VERSION}. " \
                               "Drop the `return`, or use `void`, to keep it from waiting.")
          else
            warn_about(script, "This script returns a promise, which comes back as {} today. #{NEXT_VERSION} " \
                               "will wait for it and return its value, or raise if it rejects. Prefix the " \
                               "expression with `void` to keep it from waiting.")
          end
        end

        def warn_about_node(script, value, replacement)
          warn_about(script, "Node#evaluate returns #{value} as {} today, and will return #{replacement} in " \
                             "#{NEXT_VERSION}. Check the code that uses the result.")
        end

        def warn_about_nodes(script, result)
          nodes = properties(result, ownProperties: true).any? { |p| p.dig("value", "subtype") == "node" }
          warn_about_node(script, "DOM nodes in an array", "Ferrum::Node") if nodes
        end

        def properties(result, **options)
          @page.command("Runtime.getProperties", objectId: result["objectId"], **options)["result"]
        end

        def warn_about(script, message)
          excerpt = script.code.lines.first.to_s.strip
          excerpt = "#{excerpt[0, 60]}…" if excerpt.length > 60 || script.code.lines.size > 1
          Utils::Deprecate.warn("#{message} Set FERRUM_JS_API=new to run it the #{NEXT_VERSION} way now." \
                                "\n  script: #{excerpt}", user_code: true)
        end
      end
    end
  end
end

# frozen_string_literal: true

require "singleton"

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
    # Evaluates and executes JavaScript in a frame's execution context via
    # `Runtime.callFunctionOn`, converting arguments and return values
    # between Ruby and JS, and resolving object/array/node results into Ruby
    # equivalents. A reference back to an enclosing object becomes
    # {CyclicObject}.
    #
    module Runtime
      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f
      DEEP_SERIALIZATION = {
        serialization: "deep",
        additionalParameters: { maxNodeDepth: 0, includeShadowTree: "none" }
      }.freeze
      UNSERIALIZABLE_NUMBERS = {
        "NaN" => Float::NAN,
        "-0" => -0.0,
        "Infinity" => Float::INFINITY,
        "-Infinity" => -Float::INFINITY
      }.freeze

      #
      # Evaluate and return result for given JS expression.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Array] args
      #   Additional arguments to pass to the JavaScript code.
      #
      # @example
      #   browser.evaluate("[window.scrollX, window.scrollY]")
      #
      def evaluate(expression, *args)
        expression = format("function() { return %s }", expression)
        call(expression: expression, arguments: args)
      end

      #
      # Evaluate asynchronous expression and return result.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Integer] wait
      #   How long we should wait for Promise to resolve or reject.
      #
      # @param [Array] args
      #   Additional arguments to pass to the JavaScript code.
      #
      # @example
      #   browser.evaluate_async(%(arguments[0]({foo: "bar"})), 5) # => { "foo" => "bar" }
      #
      def evaluate_async(expression, wait, *args)
        template = <<~JS
          function() {
            return new Promise((__f, __r) => {
              try {
                arguments[arguments.length] = r => __f(r);
                arguments.length = arguments.length + 1;
                setTimeout(() => __r(new Error("timed out promise")), %s);
                %s
              } catch(error) {
                __r(error);
              }
            });
          }
        JS

        expression = format(template, wait * 1000, expression)
        call(expression: expression, arguments: args, awaitPromise: true)
      end

      #
      # Execute expression. Doesn't return the result.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Array] args
      #   Additional arguments to pass to the JavaScript code.
      #
      # @example
      #   browser.execute(%(1 + 1)) # => true
      #
      def execute(expression, *args)
        expression = format("function() { %s }", expression)
        call(expression: expression, arguments: args, handle: false, returnByValue: true)
        true
      end

      #
      # Evaluates a raw JS function declaration (unlike {#evaluate}, which
      # wraps the given expression in one), optionally on a specific remote
      # object instead of the frame's global execution context.
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
      def evaluate_func(expression, *args, on: nil)
        call(expression: expression, arguments: args, on: on)
      end

      #
      # Evaluates an expression against a given node's remote object (+this+
      # refers to the node), returning the raw JS value rather than
      # resolving it to a {Node}/Hash/Array.
      #
      # @param [Node] node
      #   The node to evaluate the expression on.
      #
      # @param [String] expression
      #   The JavaScript to evaluate.
      #
      # @param [Boolean] by_value
      #   Whether to return the plain JS value instead of a handle.
      #
      # @param [Integer] wait
      #   Passed through to the underlying `Runtime.callFunctionOn` command.
      #
      def evaluate_on(node:, expression:, by_value: true, wait: 0)
        options = { handle: true }
        expression = format("function() { return %s }", expression)
        options = { handle: false, returnByValue: true } if by_value
        call(expression: expression, on: node, wait: wait, **options)
      end

      private

      def call(expression:, arguments: [], on: nil, wait: 0, handle: true, **options)
        # do not rescue -> retry if we operate on an existing node
        errors = on ? [] : [NodeNotFoundError, NoExecutionContextError]

        Utils::Attempt.with_retry(errors: errors, max: INTERMITTENT_ATTEMPTS, wait: INTERMITTENT_SLEEP) do
          params = options.dup

          params = params.merge(objectId: resolve_node(on)) if on
          params = params.merge(serializationOptions: DEEP_SERIALIZATION) if handle

          if params[:executionContextId].nil? && params[:objectId].nil?
            params = params.merge(executionContextId: execution_id!)
          end

          response = @page.command("Runtime.callFunctionOn",
                                   wait: wait, slowmoable: true,
                                   **params.merge(functionDeclaration: expression,
                                                  arguments: prepare_args(arguments)))
          handle_error(response)
          response = response["result"]

          handle ? handle_response(response) : response["value"]
        end
      end

      # FIXME: We should have a central place to handle all type of errors
      def handle_error(response)
        details = response["exceptionDetails"]
        return unless details

        case details.dig("exception", "description")
        when /\AError: timed out promise/
          raise ScriptTimeoutError
        else
          raise JavaScriptError, details
        end
      end

      def handle_response(response)
        deserialize(response["deepSerializedValue"])
      end

      def deserialize(serialized, references = {}, path = [])
        reference = serialized["weakLocalObjectReference"]
        if reference
          return cyclic_object if path.include?(reference)

          serialized = references[reference] ||= serialized
          path += [reference]
        end

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
          value.map { |v| deserialize(v, references, path) }
        when "object"
          value.to_h { |k, v| [k, deserialize(v, references, path)] }
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
          if arg.is_a?(Node)
            { objectId: resolve_node(arg) }
          elsif arg.is_a?(Hash) && arg["objectId"]
            { objectId: arg["objectId"] }
          else
            { value: arg }
          end
        end
      end

      def cyclic_object
        CyclicObject.instance
      end
    end
  end
end

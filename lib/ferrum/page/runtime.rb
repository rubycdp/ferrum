# frozen_string_literal: true

module Ferrum
  class Page
    module Runtime
      EXECUTE_OPTIONS = {
        returnByValue: true,
        functionDeclaration: %Q(function() { %s })
      }.freeze
      DEFAULT_OPTIONS = {
        functionDeclaration: %Q(function() { return %s })
      }.freeze
      EVALUATE_ASYNC_OPTIONS = {
        awaitPromise: true,
        functionDeclaration: %Q(
          function() {
           return new Promise((__resolve, __reject) => {
             try {
               arguments[arguments.length] = r => __resolve(r);
               arguments.length = arguments.length + 1;
               setTimeout(() => __reject(new Error("timed out promise")), %s);
               %s
             } catch(error) {
               __reject(error);
             }
           });
          }
        )
      }.freeze

      def evaluate(expression, *args)
        response = call(expression, nil, nil, *args)
        handle(response)
      end

      def evaluate_on(node:, expression:, by_value: true, timeout: 0)
        object_id = command("DOM.resolveNode", nodeId: node.node_id).dig("object", "objectId")
        options = DEFAULT_OPTIONS.merge(objectId: object_id)
        options[:functionDeclaration] = options[:functionDeclaration] % expression
        options.merge!(returnByValue: by_value)

        response = command("Runtime.callFunctionOn", timeout: timeout, **options)
          .dig("result").tap { |r| handle_error(r) }

        by_value ? response.dig("value") : handle(response)
      end

      def evaluate_async(expression, wait_time, *args)
        response = call(expression, wait_time * 1000, EVALUATE_ASYNC_OPTIONS, *args)
        handle(response)
      end

      def execute(expression, *args)
        call(expression, nil, EXECUTE_OPTIONS, *args)
        true
      end

      private

      def call(expression, wait_time, options = nil, *args)
        options ||= {}
        args = prepare_args(args)

        options = DEFAULT_OPTIONS.merge(options)
        expression = [wait_time, expression] if wait_time
        options[:functionDeclaration] = options[:functionDeclaration] % expression
        options = options.merge(arguments: args)
        unless options[:executionContextId]
          options = options.merge(executionContextId: execution_context_id)
        end

        begin
          attempts ||= 1
          response = command("Runtime.callFunctionOn", **options)
          response.dig("result").tap { |r| handle_error(r) }
        rescue BrowserError => e
          case e.message
          when "No node with given id found",
               "Could not find node with given id",
               "Cannot find context with specified id"
            sleep 0.1
            attempts += 1
            options = options.merge(executionContextId: execution_context_id)
            retry if attempts <= 3
          end
        end
      end

      # FIXME: We should have a central place to handle all type of errors
      def handle_error(result)
        return if result["subtype"] != "error"

        case result["description"]
        when /\AError: timed out promise/
          raise ScriptTimeoutError
        else
          raise JavaScriptError.new(result)
        end
      end

      def prepare_args(args)
        args.map do |arg|
          if arg.is_a?(Node)
            resolved = command("DOM.resolveNode", nodeId: arg.node_id)
            { objectId: resolved["object"]["objectId"] }
          elsif arg.is_a?(Hash) && arg["objectId"]
            { objectId: arg["objectId"] }
          else
            { value: arg }
          end
        end
      end

      def handle(response)
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
            begin
              node_id = command("DOM.requestNode", objectId: object_id)["nodeId"]
              desc = command("DOM.describeNode", nodeId: node_id)["node"]
              Node.new(self, target_id, node_id, desc)
            rescue BrowserError => e
              # Node has disappeared while we were trying to get it
              raise if e.message != "Could not find node with given id"
            end
          when "array"
            reduce_props(object_id, []) do |memo, key, value|
              next(memo) unless (Integer(key) rescue nil)
              value = value["objectId"] ? handle(value) : value["value"]
              memo.insert(key.to_i, value)
            end.compact
          when "date"
            response["description"]
          when "null"
            nil
          else
            reduce_props(object_id, {}) do |memo, key, value|
              value = value["objectId"] ? handle(value) : value["value"]
              memo.merge(key => value)
            end
          end
        end
      end

      def reduce_props(object_id, to)
        if cyclic?(object_id).dig("result", "value")
          return "(cyclic structure)"
        else
          props = command("Runtime.getProperties", objectId: object_id)
          props["result"].reduce(to) do |memo, prop|
            next(memo) unless prop["enumerable"]
            yield(memo, prop["name"], prop["value"])
          end
        end
      end

      def cyclic?(object_id)
        command("Runtime.callFunctionOn",
                objectId: object_id,
                returnByValue: true,
                functionDeclaration: <<~JS
                  function() {
                    if (Array.isArray(this) &&
                        this.every(e => e instanceof Node)) {
                      return false;
                    }

                    try {
                      JSON.stringify(this);
                      return false;
                    } catch (e) {
                      return true;
                    }
                  }
                JS
               )
      end
    end
  end
end

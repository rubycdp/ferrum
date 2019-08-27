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
        call(*args, expression: expression)
      end

      def evaluate_async(expression, wait_time, *args)
        call(*args, expression: expression, wait_time: wait_time * 1000, **EVALUATE_ASYNC_OPTIONS)
      end

      def execute(expression, *args)
        call(*args, expression: expression, handle: false, **EXECUTE_OPTIONS)
        true
      end

      def evaluate_on(node:, expression:, by_value: true, timeout: 0)
        rescue_intermittent_error do
          response = command("DOM.resolveNode", nodeId: node.node_id)
          object_id = response.dig("object", "objectId")
          options = DEFAULT_OPTIONS.merge(objectId: object_id)
          options[:functionDeclaration] = options[:functionDeclaration] % expression
          options.merge!(returnByValue: by_value)

          response = command("Runtime.callFunctionOn",
                             timeout: timeout,
                             **options)["result"].tap { |r| handle_error(r) }

          by_value ? response.dig("value") : handle_response(response)
        end
      end

      private

      def call(*args, expression:, wait_time: nil, handle: true, **options)
        rescue_intermittent_error do
          arguments = prepare_args(args)
          params = DEFAULT_OPTIONS.merge(options)
          expression = [wait_time, expression] if wait_time
          params[:functionDeclaration] = params[:functionDeclaration] % expression
          params = params.merge(arguments: arguments)
          unless params[:executionContextId]
            params = params.merge(executionContextId: execution_context_id)
          end

          response = command("Runtime.callFunctionOn",
                             **params)["result"].tap { |r| handle_error(r) }

          handle ? handle_response(response) : response
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

      def handle_response(response)
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
              # We cannot store object_id in the node because page can be reloaded
              # and node destroyed so we need to retrieve it each time for given id.
              # Though we can try to subscribe to `DOM.childNodeRemoved` and
              # `DOM.childNodeInserted` in the future.
              node_id = command("DOM.requestNode", objectId: object_id)["nodeId"]
              description = command("DOM.describeNode", nodeId: node_id)["node"]
              Node.new(self, target_id, node_id, description)
          when "array"
            reduce_props(object_id, []) do |memo, key, value|
              next(memo) unless (Integer(key) rescue nil)
              value = value["objectId"] ? handle_response(value) : value["value"]
              memo.insert(key.to_i, value)
            end.compact
          when "date"
            response["description"]
          when "null"
            nil
          else
            reduce_props(object_id, {}) do |memo, key, value|
              value = value["objectId"] ? handle_response(value) : value["value"]
              memo.merge(key => value)
            end
          end
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

      def rescue_intermittent_error(max = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i)
        attempts ||= 0
        yield
      rescue BrowserError => e
        case e.message
        when "No node with given id found",          # Node has disappeared while we were trying to get it
             "Could not find node with given id",
             "Cannot find context with specified id" # Context is lost, page is reloading
          sleep ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f
          attempts += 1
          attempts < max ? retry : raise
        end
      end
    end
  end
end

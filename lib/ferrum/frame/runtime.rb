# frozen_string_literal: true

require "singleton"

module Ferrum
  class Frame
    module Runtime
      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f

      EXECUTE_OPTIONS = {
        returnByValue: true,
        functionDeclaration: %(function() { %s })
      }.freeze
      DEFAULT_OPTIONS = {
        functionDeclaration: %(function() { return %s })
      }.freeze
      EVALUATE_ASYNC_OPTIONS = {
        awaitPromise: true,
        functionDeclaration: %(
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

      SCRIPT_SRC_TAG = <<~JS
        const script = document.createElement("script");
        script.src = arguments[0];
        script.type = arguments[1];
        script.onload = arguments[2];
        document.head.appendChild(script);
      JS
      SCRIPT_TEXT_TAG = <<~JS
        const script = document.createElement("script");
        script.text = arguments[0];
        script.type = arguments[1];
        document.head.appendChild(script);
        arguments[2]();
      JS
      STYLE_TAG = <<~JS
        const style = document.createElement("style");
        style.type = "text/css";
        style.appendChild(document.createTextNode(arguments[0]));
        document.head.appendChild(style);
        arguments[1]();
      JS
      LINK_TAG = <<~JS
        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = arguments[0];
        link.onload = arguments[1];
        document.head.appendChild(link);
      JS

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

      def evaluate_on(node:, expression:, by_value: true, wait: 0)
        errors = [NodeNotFoundError, NoExecutionContextError]
        attempts, sleep = INTERMITTENT_ATTEMPTS, INTERMITTENT_SLEEP

        Ferrum.with_attempts(errors: errors, max: attempts, wait: sleep) do
          response = @page.command("DOM.resolveNode", nodeId: node.node_id)
          object_id = response.dig("object", "objectId")
          options = DEFAULT_OPTIONS.merge(objectId: object_id)
          options[:functionDeclaration] = options[:functionDeclaration] % expression
          options.merge!(returnByValue: by_value)

          response = @page.command("Runtime.callFunctionOn",
                                   wait: wait, slowmoable: true,
                                   **options)
          handle_error(response)
          response = response["result"]

          by_value ? response.dig("value") : handle_response(response)
        end
      end

      def add_script_tag(url: nil, path: nil, content: nil, type: "text/javascript")
        expr, *args = if url
                        [SCRIPT_SRC_TAG, url, type]
                      elsif path || content
                        if path
                          content = File.read(path)
                          content += "\n//# sourceURL=#{path}"
                        end
                        [SCRIPT_TEXT_TAG, content, type]
                      end

        evaluate_async(expr, @page.timeout, *args)
      end

      def add_style_tag(url: nil, path: nil, content: nil)
        expr, *args = if url
                        [LINK_TAG, url]
                      elsif path || content
                        if path
                          content = File.read(path)
                          content += "\n//# sourceURL=#{path}"
                        end
                        [STYLE_TAG, content]
                      end

        evaluate_async(expr, @page.timeout, *args)
      end

      private

      def call(*args, expression:, wait_time: nil, handle: true, **options)
        errors = [NodeNotFoundError, NoExecutionContextError]
        attempts, sleep = INTERMITTENT_ATTEMPTS, INTERMITTENT_SLEEP

        Ferrum.with_attempts(errors: errors, max: attempts, wait: sleep) do
          arguments = prepare_args(args)
          params = DEFAULT_OPTIONS.merge(options)
          expression = [wait_time, expression] if wait_time
          params[:functionDeclaration] = params[:functionDeclaration] % expression
          params = params.merge(arguments: arguments)
          unless params[:executionContextId]
            params = params.merge(executionContextId: execution_id)
          end

          response = @page.command("Runtime.callFunctionOn",
                                   slowmoable: true,
                                   **params)
          handle_error(response)
          response = response["result"]

          handle ? handle_response(response) : response
        end
      end

      # FIXME: We should have a central place to handle all type of errors
      def handle_error(response)
        result = response["result"]
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
              node_id = @page.command("DOM.requestNode", objectId: object_id)["nodeId"]
              description = @page.command("DOM.describeNode", nodeId: node_id)["node"]
              Node.new(self, @page.target_id, node_id, description)
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
            resolved = @page.command("DOM.resolveNode", nodeId: arg.node_id)
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
          return to.is_a?(Array) ? [cyclic_object] : cyclic_object
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

  class CyclicObject
    include Singleton

    def inspect
      %(#<#{self.class} JavaScript object that cannot be represented in Ruby>)
    end
  end
end

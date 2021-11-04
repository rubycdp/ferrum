# frozen_string_literal: true

require "singleton"

module Ferrum
  class CyclicObject
    include Singleton

    def inspect
      %(#<#{self.class} JavaScript object that cannot be represented in Ruby>)
    end
  end

  class Frame
    module Runtime
      INTERMITTENT_ATTEMPTS = ENV.fetch("FERRUM_INTERMITTENT_ATTEMPTS", 6).to_i
      INTERMITTENT_SLEEP = ENV.fetch("FERRUM_INTERMITTENT_SLEEP", 0.1).to_f

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
        expression = format("function() { return %s }", expression)
        call(expression: expression, arguments: args)
      end

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

      def execute(expression, *args)
        expression = format("function() { %s }", expression)
        call(expression: expression, arguments: args, handle: false, returnByValue: true)
        true
      end

      def evaluate_func(expression, *args, on: nil)
        call(expression: expression, arguments: args, on: on)
      end

      def evaluate_on(node:, expression:, by_value: true, wait: 0)
        options = { handle: true }
        expression = format("function() { return %s }", expression)
        options = { handle: false, returnByValue: true } if by_value
        call(expression: expression, on: node, wait: wait, **options)
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

      def call(expression:, arguments: [], on: nil, wait: 0, handle: true, **options)
        errors = [NodeNotFoundError, NoExecutionContextError]
        sleep = INTERMITTENT_SLEEP
        attempts = INTERMITTENT_ATTEMPTS

        Ferrum.with_attempts(errors: errors, max: attempts, wait: sleep) do
          params = options.dup

          if on
            response = @page.command("DOM.resolveNode", nodeId: on.node_id)
            object_id = response.dig("object", "objectId")
            params = params.merge(objectId: object_id)
          end

          if params[:executionContextId].nil? && params[:objectId].nil?
            params = params.merge(executionContextId: execution_id)
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
        result = response["result"]
        return if result["subtype"] != "error"

        case result["description"]
        when /\AError: timed out promise/
          raise ScriptTimeoutError
        else
          raise JavaScriptError.new(result, response.dig("exceptionDetails", "stackTrace"))
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
              next(memo) unless Integer(key, exception: false)

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

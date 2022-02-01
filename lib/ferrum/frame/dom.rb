# frozen_string_literal: true

# RemoteObjectId is from a JavaScript world, and corresponds to any JavaScript
# object, including JS wrappers for DOM nodes. There is a way to convert between
# node ids and remote object ids (DOM.requestNode and DOM.resolveNode).
#
# NodeId is used for inspection, when backend tracks the node and sends updates to
# the frontend. If you somehow got NodeId over protocol, backend should have
# pushed to the frontend all of it's ancestors up to the Document node via
# DOM.setChildNodes. After that, frontend is always kept up-to-date about anything
# happening to the node.
#
# BackendNodeId is just a unique identifier for a node. Obtaining it does not send
# any updates, for example, the node may be destroyed without any notification.
# This is a way to keep a reference to the Node, when you don't necessarily want
# to keep track of it. One example would be linking to the node from performance
# data (e.g. relayout root node). BackendNodeId may be either resolved to
# inspected node (DOM.pushNodesByBackendIdsToFrontend) or described in more
# details (DOM.describeNode).
module Ferrum
  class Frame
    module DOM
      def current_url
        evaluate("window.top.location.href")
      end

      def current_title
        evaluate("window.top.document.title")
      end

      def doctype
        evaluate("document.doctype && new XMLSerializer().serializeToString(document.doctype)")
      end

      def body
        evaluate("document.documentElement.outerHTML")
      end

      def xpath(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            let results = [];
            within ||= document

            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            for (let i = 0; i < xpath.snapshotLength; i++) {
              results.push(xpath.snapshotItem(i));
            }

            return results;
          }
        JS

        evaluate_func(expr, selector, within)
      end

      def at_xpath(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            return xpath.snapshotItem(0);
          }
        JS
        evaluate_func(expr, selector, within)
      end

      def wait_for_xpath(xpath, **options)
        expr = <<~JS
          function(selector) {
            return document.evaluate(selector, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue;
          }
        JS

        wait_for_selector(xpath, expr, **options)
      end

      def css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return Array.from(within.querySelectorAll(selector));
          }
        JS

        evaluate_func(expr, selector, within)
      end

      def at_css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return within.querySelector(selector);
          }
        JS

        evaluate_func(expr, selector, within)
      end

      def wait_for_css(css, **options)
        expr = <<~JS
          function(selector) {
            return document.querySelector(selector);
          }
        JS

        wait_for_selector(css, expr, **options)
      end

      private

      def wait_for_selector(selector, find_element_expression, timeout: 3000, interval: 100)
        expr = <<~JS
          function(selector, findElementExpression, timeout, interval) {
            var attempts = 0;
            var max = timeout / interval;
            var wrapperFunction = function(expression) {
              return "{ return " + expression + " };";
            }
            function waitForElement(resolve, reject) {
              if (attempts > ((max < 1) ? 1 : max)) {
                return reject(new Error("Not found element match the selector: " + selector));
              }
              var element = new Function(wrapperFunction(findElementExpression))()(selector);
              if (element !== null) {
                return resolve(element);
              }
              setTimeout(function () {
                waitForElement(resolve, reject);
              }, interval);
              attempts++;
            }
            return new Promise(function (resolve, reject) {
              waitForElement(resolve, reject);
            });
          }
        JS

        evaluate_func(expr, selector, find_element_expression, timeout, interval, awaitPromise: true)
      end
    end
  end
end

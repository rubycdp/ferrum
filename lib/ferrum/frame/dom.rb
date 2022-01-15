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

      def wait_for_selector(css: nil, xpath: nil, timeout: 5000, interval: 100)
        evaluate_func(%(
          function(selector, isXpath, timeout, interval) {
            var attempts = 0;
            var max = timeout / interval;
            function waitForSelector(resolve, reject) {
              if (attempts > ((max < 1) ? 1 : max)) {
                return reject(new Error("Not found element match the selector: " + selector));
              }
              var element = isXpath
                ? document.
                  evaluate(selector, document, null, XPathResult.FIRST_ORDERED_NODE_TYPE, null).singleNodeValue
                : document.querySelector(selector);
              if (element !== null) {
                return resolve(element);
              }
              setTimeout(function () {
                waitForSelector(resolve, reject);
              }, interval);
              attempts++;
            }
            return new Promise(function (resolve, reject) {
              waitForSelector(resolve, reject);
            });
          }
        ), css || xpath, css.nil? && !xpath.nil?, timeout, interval, awaitPromise: true)
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
    end
  end
end

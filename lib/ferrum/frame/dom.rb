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
        code = <<~JS
          let selector = arguments[0];
          let within = arguments[1] || document;
          let results = [];

          let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          for (let i = 0; i < xpath.snapshotLength; i++) {
            results.push(xpath.snapshotItem(i));
          }

          arguments[2](results);
        JS

        evaluate_async(code, @page.timeout, selector, within)
      end

      def at_xpath(selector, within: nil)
        code = <<~JS
          let selector = arguments[0];
          let within = arguments[1] || document;
          let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
          let result = xpath.snapshotItem(0);
          arguments[2](result);
        JS

        evaluate_async(code, @page.timeout, selector, within)
      end

      def css(selector, within: nil)
        code = <<~JS
          let selector = arguments[0];
          let within = arguments[1] || document;
          let results = within.querySelectorAll(selector);
          arguments[2](results);
        JS

        evaluate_async(code, @page.timeout, selector, within)
      end

      def at_css(selector, within: nil)
        code = <<~JS
          let selector = arguments[0];
          let within = arguments[1] || document;
          let result = within.querySelector(selector);
          arguments[2](result);
        JS

        evaluate_async(code, @page.timeout, selector, within)
      end
    end
  end
end

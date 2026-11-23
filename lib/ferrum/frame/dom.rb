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
# data (e.g. re-layout root node). BackendNodeId may be either resolved to
# inspected node (DOM.pushNodesByBackendIdsToFrontend) or described in more
# details (DOM.describeNode).
module Ferrum
  class Frame
    #
    # Evaluates and executes JavaScript to query and manipulate a frame's
    # DOM: reading the URL, title, doctype, and HTML, finding nodes by
    # XPath or CSS selector, and injecting `<script>`, `<style>`, and
    # `<link>` tags.
    #
    module DOM
      WAIT_INTERVAL = 0.05
      WAIT_FOR_SELECTOR_DEPRECATED = "wait_for_selector will be removed in Ferrum 0.22. Use wait_css(selector) or " \
                                     "wait_xpath(selector) instead."
      SCRIPT_SRC_TAG = <<~JS
        function(url, type) {
          const script = document.createElement("script");
          script.src = url;
          script.type = type;
          document.head.appendChild(script);
          return new Promise(resolve => script.onload = resolve);
        }
      JS
      SCRIPT_TEXT_TAG = <<~JS
        function(content, type) {
          const script = document.createElement("script");
          script.text = content;
          script.type = type;
          document.head.appendChild(script);
        }
      JS
      STYLE_TAG = <<~JS
        function(content) {
          const style = document.createElement("style");
          style.type = "text/css";
          style.appendChild(document.createTextNode(content));
          document.head.appendChild(style);
        }
      JS
      LINK_TAG = <<~JS
        function(url) {
          const link = document.createElement("link");
          link.rel = "stylesheet";
          link.href = url;
          document.head.appendChild(link);
          return new Promise(resolve => link.onload = resolve);
        }
      JS

      #
      # @deprecated Will be removed in Ferrum 0.22. Use `page.url`, or
      #   `frame.page.url` from a frame.
      #
      # Returns current top window `location href`.
      #
      # @return [String]
      #   The window's current URL.
      #
      # @raise [TimeoutError]
      #
      def current_url
        Utils::Deprecate.warn(
          "#current_url will be removed in Ferrum 0.22. Use page.url, or frame.page.url from a frame, " \
          "frame.url is the frame's own URL."
        )
        evaluate("window.top.location.href")
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use `page.title`, or
      #   `frame.page.title` from a frame.
      #
      # Returns current top window title.
      #
      # @return [String]
      #   The window's current title.
      #
      # @raise [TimeoutError]
      #
      def current_title
        Utils::Deprecate.warn(
          "#current_title will be removed in Ferrum 0.22. Use page.title, or frame.page.title from a frame, " \
          "frame.title is the frame's own title."
        )
        evaluate("window.top.document.title")
      end

      #
      # Returns current document's doctype declaration.
      #
      # @return [String, nil]
      #   The serialized `<!DOCTYPE ...>` declaration, or +nil+ if the
      #   document has none.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://example.com")
      #   browser.doctype # => "<!DOCTYPE html>"
      #
      def doctype
        evaluate("document.doctype && new XMLSerializer().serializeToString(document.doctype)")
      end

      #
      # Returns the HTML of the whole document, `<html>` included.
      #
      # @return [String]
      #   The document's `outerHTML`, empty when it has no root element.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://google.com/")
      #   browser.html # => '<html itemscope="" itemtype="http://schema.org/WebPage" lang="ru"><head>...
      #
      def html
        evaluate("document.documentElement?.outerHTML") || ""
      end

      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#html}, it was never
      #   only `<body>`.
      #
      # @return [String]
      #
      # @raise [TimeoutError]
      #
      def body
        Utils::Deprecate.warn("body will be removed in Ferrum 0.22. Use html instead.", user_code: true)
        html
      end

      #
      # Returns the element in which the window is embedded.
      #
      # @return [Node, nil]
      #   The element in which the window is embedded, `nil` for the main frame
      #   and for a frame from a different origin than its parent.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://developer.mozilla.org/en-US/docs/Web/HTML/Element/iframe")
      #   frame = browser.frames.last
      #   frame.frame_element # => [Node]
      #   frame.parent.parent.parent.frame_element # => nil
      #
      def frame_element
        evaluate("window.frameElement")
      end

      #
      # Finds nodes by using a XPath selector.
      #
      # @param [String] selector
      #   The XPath selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Array<Node>]
      #   The matching nodes.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.xpath("//a[@aria-label='Issues you created']") # => [Node]
      #
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

        evaluate(expr, selector, within)
      end

      #
      # Finds a node by using a XPath selector.
      #
      # @param [String] selector
      #   The XPath selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Node, nil]
      #   The matching node.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.at_xpath("//a[@aria-label='Issues you created']") # => Node
      #
      def at_xpath(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            let xpath = document.evaluate(selector, within, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            return xpath.snapshotItem(0);
          }
        JS
        evaluate(expr, selector, within)
      end

      #
      # Finds nodes by using a CSS path selector.
      #
      # @param [String] selector
      #   The CSS path selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Array<Node>]
      #   The matching nodes.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.css("a[aria-label='Issues you created']") # => [Node]
      #
      def css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return Array.from(within.querySelectorAll(selector));
          }
        JS

        evaluate(expr, selector, within)
      end

      #
      # Finds a node by using a CSS path selector.
      #
      # @param [String] selector
      #   The CSS path selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @return [Node, nil]
      #   The matching node.
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.go_to("https://github.com/")
      #   browser.at_css("a[aria-label='Issues you created']") # => Node
      #
      def at_css(selector, within: nil)
        expr = <<~JS
          function(selector, within) {
            within ||= document
            return within.querySelector(selector);
          }
        JS

        evaluate(expr, selector, within)
      end

      #
      # Polls {#at_css} until a node matches the selector.
      #
      # @param [String] selector
      #   The CSS selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long to keep trying, the page's `timeout` by default.
      #
      # @param [Numeric] interval
      #   Seconds to sleep between the attempts.
      #
      # @return [Node, nil]
      #   The matching node, `nil` if none shows up in time.
      #
      # @example
      #   browser.wait_css("#appears_later") # => Node
      #
      def wait_css(selector, within: nil, timeout: nil, interval: WAIT_INTERVAL)
        Utils::Poll.call(timeout || @page.timeout, interval) { at_css(selector, within: within) }
      end

      #
      # Same as {#wait_css}, but raises if no node matches in time.
      #
      # @param [String] selector
      #
      # @param [Hash] options
      #   The options of {#wait_css}.
      #
      # @return [Node]
      #
      # @raise [TimeoutError]
      #   If no node matches in time.
      #
      def wait_css!(selector, **options)
        wait_css(selector, **options) || raise(TimeoutError)
      end

      #
      # Polls {#at_xpath} until a node matches the selector.
      #
      # @param [String] selector
      #   The XPath selector.
      #
      # @param [Node, nil] within
      #   The parent node to search within.
      #
      # @param [Numeric, Deadline, nil] timeout
      #   How long to keep trying, the page's `timeout` by default.
      #
      # @param [Numeric] interval
      #   Seconds to sleep between the attempts.
      #
      # @return [Node, nil]
      #   The matching node, `nil` if none shows up in time.
      #
      # @example
      #   browser.wait_xpath("//div[@id='appears_later']") # => Node
      #
      def wait_xpath(selector, within: nil, timeout: nil, interval: WAIT_INTERVAL)
        Utils::Poll.call(timeout || @page.timeout, interval) { at_xpath(selector, within: within) }
      end

      #
      # Same as {#wait_xpath}, but raises if no node matches in time.
      #
      # @param [String] selector
      #
      # @param [Hash] options
      #   The options of {#wait_xpath}.
      #
      # @return [Node]
      #
      # @raise [TimeoutError]
      #   If no node matches in time.
      #
      def wait_xpath!(selector, **options)
        wait_xpath(selector, **options) || raise(TimeoutError)
      end

      #
      # Finds a node by using a CSS path or XPath selector, retrying until
      # it appears or `timeout` elapses.
      #
      # @deprecated Will be removed in Ferrum 0.22. Use {#wait_css} or {#wait_xpath}.
      #
      # @param [String, nil] css
      #
      # @param [String, nil] xpath
      #
      # @param [Node, nil] within
      #
      # @param [Numeric, Deadline] timeout
      #
      # @param [Float, Integer] interval
      #
      # @return [Node, nil]
      #
      # @raise [ArgumentError]
      #   If neither or both of `css`/`xpath` are given.
      #
      def wait_for_selector(css: nil, xpath: nil, within: nil, timeout: @page.timeout, interval: WAIT_INTERVAL)
        Utils::Deprecate.warn(WAIT_FOR_SELECTOR_DEPRECATED, user_code: true)
        raise ArgumentError, "pass either `css:` or `xpath:`" if (css && xpath) || !(css || xpath)

        options = { within: within, timeout: timeout, interval: interval }
        css ? wait_css(css, **options) : wait_xpath(xpath, **options)
      end

      #
      # Adds a `<script>` tag to the document.
      #
      # @param [String, nil] url
      #
      # @param [String, nil] path
      #
      # @param [String, nil] content
      #
      # @param [String] type
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.add_script_tag(url: "http://example.com/stylesheet.css") # => true
      #
      def add_script_tag(url: nil, path: nil, content: nil, type: "text/javascript")
        if url
          evaluate(SCRIPT_SRC_TAG, url, type)
        elsif path || content
          if path
            content = File.read(path)
            content += "\n//# sourceURL=#{path}"
          end
          evaluate(SCRIPT_TEXT_TAG, content, type)
        end

        true
      end

      #
      # Adds a `<style>` tag to the document.
      #
      # @param [String, nil] url
      #
      # @param [String, nil] path
      #
      # @param [String, nil] content
      #
      # @raise [TimeoutError]
      #
      # @example
      #   browser.add_style_tag(content: "h1 { font-size: 40px; }") # => true
      #
      def add_style_tag(url: nil, path: nil, content: nil)
        if url
          evaluate(LINK_TAG, url)
        elsif path || content
          if path
            content = File.read(path)
            content += "\n//# sourceURL=#{path}"
          end
          evaluate(STYLE_TAG, content)
        end

        true
      end
    end
  end
end

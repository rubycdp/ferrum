# frozen_string_literal: true

describe Ferrum::Frame::DOM do
  describe "#add_script_tag" do
    it "adds by url" do
      browser.go_to
      expect do
        browser.evaluate("$('a').first().text()")
      end.to raise_error(Ferrum::JavaScriptError)

      browser.add_script_tag(url: "/jquery.min.js")

      expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
    end

    it "adds by path" do
      browser.go_to
      path = "#{Ferrum::Application::FERRUM_PUBLIC}/jquery-3.7.1.min.js"
      expect do
        browser.evaluate("$('a').first().text()")
      end.to raise_error(Ferrum::JavaScriptError)

      browser.add_script_tag(path: path)

      expect(browser.evaluate("$('a').first().text()")).to eq("Relative")
    end

    it "adds by content" do
      browser.go_to

      browser.add_script_tag(content: "function yay() { return 'yay!'; }")

      expect(browser.evaluate("yay()")).to eq("yay!")
    end
  end

  describe "#add_style_tag" do
    let(:font_size) do
      <<~JS
        window
          .getComputedStyle(document.querySelector('a'))
          .getPropertyValue('font-size')
      JS
    end

    it "adds by url" do
      browser.go_to
      expect(browser.evaluate(font_size)).to eq("16px")

      browser.add_style_tag(url: "/add_style_tag.css")

      expect(browser.evaluate(font_size)).to eq("50px")
    end

    it "adds by path" do
      browser.go_to
      path = "#{Ferrum::Application::FERRUM_PUBLIC}/add_style_tag.css"
      expect(browser.evaluate(font_size)).to eq("16px")

      browser.add_style_tag(path: path)

      expect(browser.evaluate(font_size)).to eq("50px")
    end

    it "adds by content" do
      browser.go_to

      browser.add_style_tag(content: "a { font-size: 20px; }")

      expect(browser.evaluate(font_size)).to eq("20px")
    end
  end

  describe "#current_url" do
    around do |example|
      Ferrum::Utils::Deprecate.reset!
      example.run
      Ferrum::Utils::Deprecate.reset!
    end

    it "returns the top window's url and warns that it is deprecated" do
      page.go_to
      page.execute(%(document.body.innerHTML += "<iframe src='/slow' name='frame'>"))
      frame = page.at_xpath("//iframe[@name='frame']").frame

      expect { expect(frame.current_url).to eq(page.url) }
        .to output(/#current_url will be removed in Ferrum 0\.22.*called from #{__FILE__}/m).to_stderr
    end
  end

  describe "#current_title" do
    around do |example|
      Ferrum::Utils::Deprecate.reset!
      example.run
      Ferrum::Utils::Deprecate.reset!
    end

    it "returns the top window's title and warns that it is deprecated" do
      page.go_to
      page.execute(%(document.body.innerHTML += "<iframe src='/slow' name='frame'>"))
      frame = page.at_xpath("//iframe[@name='frame']").frame

      expect { expect(frame.current_title).to eq(page.title) }
        .to output(/#current_title will be removed in Ferrum 0\.22/).to_stderr
    end
  end

  describe "#doctype" do
    it "returns the doctype" do
      page.go_to("/frames")
      expect(page.doctype).to eq("<!DOCTYPE html>")

      doctype40 = %(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">)
      page.content = "#{doctype40}<html><head></head><body>Voila!</body></html>"
      expect(page.doctype).to eq(doctype40)

      page.content = ""
      expect(page.doctype).to be_nil
    end
  end

  describe "#body" do
    it "returns the body of an about:blank frame without a document" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to eq("<html><head></head><body></body></html>")
    end

    it "returns the body of an about:blank frame built by JS" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='about:blank' name='frame'>";
        var iframeDocument = document.querySelector("iframe[name='frame']").contentWindow.document;
        var content = "<html><body><p>Hello Frame</p></body></html>";
        iframeDocument.open("text/html", "replace");
        iframeDocument.write(content);
        iframeDocument.close();
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end

    it "returns the body of a frame with srcdoc" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end

    it "returns the body of a frame without src filled by JS" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe id='frame' name='frame'>"
      JS
      page.execute <<-JS
        var iframeDocument = document.querySelector("#frame").contentWindow.document;
        var content = "<html><body><p>Hello Frame</p></body></html>";
        iframeDocument.open("text/html", "replace");
        iframeDocument.write(content);
        iframeDocument.close();
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end
  end

  describe "#frame_element" do
    it "gets the frame element" do
      page.go_to("/frame_parent")

      frame_element = page.at_xpath("//iframe")
      frame = frame_element.frame
      expect(frame.frame_element).to eq(frame_element)
      expect(frame.frame_element.frame_id).to eq frame.id
      expect(frame.frame_element.attribute(:src)).to eq("/frame_child")
    end

    it "returns nil for a cross-origin frame" do
      page.go_to("/frames")

      frame = page.at_xpath("//iframe").frame
      expect(frame.frame_element).to be_nil
    end

    it "returns nil if main frame" do
      page.go_to("/frames")

      parent_frame = page.at_xpath("//iframe").frame.parent
      expect(parent_frame).to be_main
      expect(parent_frame.frame_element).to be_nil
    end

    it "supports nested frames" do
      page.go_to("/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/nested_frame_test' name='outer_frame' style='padding:200px'>"
      JS
      page.network.wait_for_idle

      outer_frame_element = page.at_xpath("//iframe[@name='outer_frame']")
      outer_frame = outer_frame_element.frame

      inner_frame_element = outer_frame.at_xpath("//iframe")
      inner_frame = inner_frame_element.frame

      expect(outer_frame.frame_element).to eq(outer_frame_element)
      expect(inner_frame.frame_element).to eq(inner_frame_element)
    end
  end

  describe "#xpath" do
    it "returns given nodes" do
      page.go_to("/with_js")
      p = page.xpath("//p[@id='remove_me']")

      expect(p.size).to eq(1)
    end

    it "supports within" do
      page.go_to("/with_js")
      p = page.xpath("//p[@id='with_content']").first

      links = page.xpath("./a", within: p)

      expect(links.size).to eq(1)
      expect(links.first.attribute(:id)).to eq("open-match")
    end

    it "throws an error on a wrong xpath" do
      page.go_to("/with_js")

      expect do
        page.xpath("#remove_me")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_xpath("//iframe[@id='buttons_frame']").frame
      expect(frame.xpath("//button").size).to eq(3)
    end
  end

  describe "#at_xpath" do
    it "returns given nodes" do
      page.go_to("/with_js")
      p = page.at_xpath("//p[@id='remove_me']")

      expect(p).not_to be_nil
    end

    it "supports within" do
      page.go_to("/with_js")
      p = page.at_xpath("//p[@id='with_content']")

      link = page.at_xpath("./a", within: p)

      expect(link).not_to be_nil
      expect(link.attribute(:id)).to eq("open-match")
    end

    it "throws an error on a wrong xpath" do
      page.go_to("/with_js")

      expect do
        page.at_xpath("#remove_me")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_xpath("//iframe[@id='buttons_frame']").frame
      expect(frame.at_xpath("//button[@id='click_me_123']")).not_to be_nil
    end

    it "works correctly when JSON is overwritten" do
      page.go_to("/index")
      page.execute("JSON = {};")
      expect { page.at_xpath("//a[text() = 'JS redirect']") }.not_to raise_error
    end
  end

  describe "#css" do
    it "returns given nodes" do
      page.go_to("/with_js")
      p = page.css("p#remove_me")

      expect(p.size).to eq(1)
    end

    it "supports within" do
      page.go_to("/with_js")
      p = page.css("p#with_content").first

      links = page.css("a", within: p)

      expect(links.size).to eq(1)
      expect(links.first.attribute(:id)).to eq("open-match")
    end

    it "throws an error on an invalid selector" do
      page.go_to("/table")

      expect do
        page.css("table tr:last")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_css("iframe#buttons_frame").frame
      expect(frame.css("button").size).to eq(3)
    end
  end

  describe "#at_css" do
    it "returns given nodes" do
      page.go_to("/with_js")
      p = page.at_css("p#remove_me")

      expect(p).not_to be_nil
    end

    it "supports within" do
      page.go_to("/with_js")
      p = page.at_css("p#with_content")

      link = page.at_css("a", within: p)

      expect(link).not_to be_nil
      expect(link.attribute(:id)).to eq("open-match")
    end

    it "throws an error on an invalid selector" do
      page.go_to("/table")

      expect do
        page.at_css("table tr:last")
      end.to raise_error(Ferrum::JavaScriptError)
    end

    it "supports inside a given frame" do
      page.go_to("/frames")
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='/buttons' id='buttons_frame'>"
      JS
      page.network.wait_for_idle

      frame = page.at_css("iframe#buttons_frame").frame
      expect(frame.at_css("button#click_me_123")).not_to be_nil
    end
  end

  describe "#wait_for_selector" do
    it "returns the node immediately when it's already present" do
      page.go_to("/with_js")

      expect(page.wait_for_selector(css: "p#remove_me")).not_to be_nil
    end

    it "waits for a css selector to appear" do
      page.go_to("/with_js")
      page.execute <<-JS
        setTimeout(function () {
          var div = document.createElement("div");
          div.id = "appears_later";
          document.body.appendChild(div);
        }, 300);
      JS

      expect(page.wait_for_selector(css: "div#appears_later", timeout: 2)).not_to be_nil
    end

    it "waits for an xpath selector to appear" do
      page.go_to("/with_js")
      page.execute <<-JS
        setTimeout(function () {
          var div = document.createElement("div");
          div.id = "appears_later";
          document.body.appendChild(div);
        }, 300);
      JS

      expect(page.wait_for_selector(xpath: "//div[@id='appears_later']", timeout: 2)).not_to be_nil
    end

    it "returns nil once timeout elapses without a match" do
      page.go_to("/with_js")

      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      node = page.wait_for_selector(css: "div#never_appears", timeout: 0.3, interval: 0.05)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at

      expect(node).to be_nil
      expect(elapsed).to be >= 0.3
    end

    it "supports within" do
      page.go_to("/with_js")
      p = page.at_css("p#with_content")

      link = page.wait_for_selector(css: "a", within: p)

      expect(link).not_to be_nil
      expect(link.attribute(:id)).to eq("open-match")
    end

    it "raises when neither css nor xpath is given" do
      expect { page.wait_for_selector }.to raise_error(ArgumentError)
    end

    it "raises when both css and xpath are given" do
      expect { page.wait_for_selector(css: "a", xpath: "//a") }.to raise_error(ArgumentError)
    end
  end
end

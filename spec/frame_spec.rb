# frozen_string_literal: true

describe Ferrum::Frame do
  describe "#at_xpath" do
    it "works correctly when JSON is overwritten" do
      page.go_to("/index")
      page.execute("JSON = {};")
      expect { page.at_xpath("//a[text() = 'JS redirect']") }.not_to raise_error
    end
  end

  it "supports selection by index" do
    page.go_to("/frames")
    frame = page.at_xpath("//iframe").frame
    expect(frame.url).to end_with("/slow")
  end

  it "supports selection by element" do
    page.go_to("/frames")
    frame = page.at_css("iframe[name]").frame
    expect(frame.url).to end_with("/slow")
  end

  it "supports selection by element without name or id" do
    page.go_to("/frames")
    frame = page.at_css("iframe:not([name]):not([id])").frame
    expect(frame.url).to end_with("/headers")
  end

  it "supports selection by element with id but no name" do
    page.go_to("/frames")
    frame = page.at_css("iframe[id]:not([name])").frame
    expect(frame.url).to end_with("/get_cookie")
  end

  it "finds main frame properly" do
    browser.go_to("/popup_frames")

    browser.at_xpath("//a[text()='pop up']").click

    expect(browser.pages.size).to eq(2)
    opened_page = browser.pages.last
    expect(opened_page.main_frame.url).to end_with("/frames")
  end

  it "finds parent frame properly" do
    page.go_to("/frames")
    parent_frame = page.at_xpath("//iframe").frame.parent
    expect(parent_frame.url).to end_with("/frames")
  end

  it "waits for the frame to load" do
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/slow' name='frame'>"
    JS

    frame = page.at_xpath("//iframe[@name='frame']").frame
    expect(frame.url).to end_with("/slow")
    expect(frame.body).to include("slow page")

    expect(page.main_frame.url).to end_with("/")
  end

  it "waits for the cross-domain frame to load" do
    page.go_to("/frames")
    expect(page.current_url).to eq(base_url("/frames"))
    frame = page.at_xpath("//iframe[@name='frame']").frame

    expect(frame.url).to end_with("/slow")
    expect(frame.body).to include("slow page")

    expect(page.current_url).to end_with("/frames")
  end

  context "with src == about:blank" do
    it "doesn't hang if no document created" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe src='about:blank' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to eq("<html><head></head><body></body></html>")
    end

    it "doesn't hang if built by JS" do
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
  end

  context "with no src attribute" do
    it "doesn't hang if the srcdoc attribute is used" do
      page.go_to
      page.execute <<-JS
        document.body.innerHTML += "<iframe srcdoc='<p>Hello Frame</p>' name='frame'>"
      JS
      frame = page.at_xpath("//iframe[@name='frame']").frame
      expect(frame.body).to include("Hello Frame")
    end

    it "doesn't hang if the frame is filled by JS" do
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

  context "with loading=lazy iframe Chrome never starts loading" do
    # Regression test for [#583]. Chrome fires Page.frameAttached for every
    # iframe in the DOM but only fires frameStoppedLoading for frames it
    # actually loads. A `loading="lazy"` iframe outside the viewport never
    # starts loading, so its Frame#state stays nil. Without the fix, the
    # idle predicate refuses to consider such frames idle and page.go_to
    # blocks for the full browser timeout (silently rescued — no error
    # is raised, the call just takes ~timeout seconds to return).
    #
    # with_timeout(1) bounds the bug path's wall-clock to 1s so a failing
    # test fails fast. The 0.5s assertion threshold leaves ~5-10x headroom
    # for the fix path (a static page load is well under 100ms).
    it "does not block page.go_to (lazy iframe in closed <details>)" do
      with_timeout(1) do
        started_at = Ferrum::Utils::ElapsedTime.monotonic_time
        page.go_to("/lazy_iframe")
        expect(Ferrum::Utils::ElapsedTime.elapsed_time(started_at)).to be < 0.5
      end

      # Load-bearing on two axes:
      # 1. Confirms we hit the bug's precondition (a frame in nil state)
      #    rather than passing because no lazy frame was attached at all.
      # 2. Guards against false-pass via Runtime.executionContextsCleared.
      #    That handler (subscribe_execution_contexts_cleared in
      #    lib/ferrum/page/frames.rb) unconditionally sets every frame's
      #    state to :stopped_loading. If it fires during navigation on
      #    some Chrome versions, the old idling? would return true and
      #    the timing assertion would pass on `main`. The nil-state
      #    postcondition catches that case.
      lazy = page.frames.reject(&:main?).first
      expect(lazy.state).to be_nil
    end

    # Scenario 2 from #583. The lazy iframe is inserted by a click handler
    # AFTER the page has loaded. The handler also triggers a same-document
    # navigation (location.hash) so idling? is re-evaluated while the
    # nil-state frame is in @frames. A full reload or cross-document
    # navigation would fire Runtime.executionContextsCleared and mask the
    # bug. Under the bug, ferrum's internal mouse_event wait on idling?
    # blocks for the full browser.timeout and raises Ferrum::TimeoutError.
    it "does not block click whose handler attaches a lazy iframe" do
      page.go_to("/lazy_iframe_via_click")

      with_timeout(1) do
        started_at = Ferrum::Utils::ElapsedTime.monotonic_time
        page.at_css("#add_iframe").click
        expect(Ferrum::Utils::ElapsedTime.elapsed_time(started_at)).to be < 0.5
      end

      # See load-bearing rationale on the scenario 1 test above.
      lazy = page.frames.reject(&:main?).first
      expect(lazy.state).to be_nil
    end

    # Same bug, exercised via reload rather than initial go_to. Under the
    # bug, page.reload raises Ferrum::TimeoutError after browser.timeout;
    # with the fix it returns quickly. The post-reload state postcondition
    # used by the other tests doesn't work here because reload fires
    # Runtime.executionContextsCleared, which overwrites the frame's state
    # to :stopped_loading by the time the postcondition would run. Capture
    # the precondition before reload instead.
    it "does not block page.reload (lazy iframe in closed <details>)" do
      page.go_to("/lazy_iframe")

      # Confirm the bug's precondition (a frame in nil state) holds before
      # reload runs, so a green test means the fix handled that state
      # rather than the test passing for an unrelated reason.
      lazy = page.frames.reject(&:main?).first
      expect(lazy.state).to be_nil

      with_timeout(1) do
        started_at = Ferrum::Utils::ElapsedTime.monotonic_time
        page.reload
        expect(Ferrum::Utils::ElapsedTime.elapsed_time(started_at)).to be < 0.5
      end
    end

    # The reporter's real-world case from #583 (two YouTube iframes side
    # by side). The all? predicate must accept multiple nil-state frames,
    # not just one. Exercises the same code path as scenario 1 but with
    # @frames.size == 3 (main + two lazies).
    it "does not block page.go_to (multiple lazy iframes outside viewport)" do
      with_timeout(1) do
        started_at = Ferrum::Utils::ElapsedTime.monotonic_time
        page.go_to("/lazy_iframes_two")
        expect(Ferrum::Utils::ElapsedTime.elapsed_time(started_at)).to be < 0.5
      end

      # See load-bearing rationale on the scenario 1 test above, applied
      # to both nil-state frames.
      lazies = page.frames.reject(&:main?)
      expect(lazies.size).to eq(2)
      expect(lazies.map(&:state)).to all(be_nil)
    end

    # Even for lazy iframes Chrome decides to load (in or near the
    # viewport), frameStartedLoading can be deferred past the main frame's
    # frameStoppedLoading. With the fix, page.go_to no longer waits on
    # nil-state frames, so it may return before such an iframe begins
    # loading. That's a deliberate behavior change: ferrum can't tell at
    # idle-check time whether a nil-state frame is one Chrome will never
    # load (the #583 bug) or one Chrome is about to load (this case).
    # Treating both as idle is the only correct choice for the never-load
    # case; for the about-to-load case, callers wait explicitly via
    # frame.body (blocks until the frame is loaded) or
    # page.network.wait_for_idle.
    it "still loads in-viewport lazy iframes (callers wait via frame.body)" do
      page.go_to("/lazy_iframe_in_viewport")

      lazy = page.frames.reject(&:main?).first
      expect(lazy.body).to include("slow page")
      expect(lazy.state).to eq(:stopped_loading)
    end
  end

  it "supports clicking in a frame", skip: true do
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/click_test' name='frame'>"
    JS
    sleep 0.5
    frame = page.at_xpath("//iframe[@name = 'frame']").frame

    log = frame.at_css("#log")
    frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "supports clicking in a frame with padding", skip: true do
    page.go_to
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/click_test' name='padded_frame' style='padding:100px;'>"
    JS
    frame = page.at_xpath("//iframe[@name = 'padded_frame']").frame

    log = frame.at_css("#log")
    frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "supports clicking in a frame nested in a frame", skip: true do
    page.go_to

    # The padding on the frame here is to differ the sizes of the two
    # frames, ensuring that their offsets are being calculated seperately.
    # This avoids a false positive where the same frame"s offset is
    # calculated twice, but the click still works because both frames had
    # the same offset.
    page.execute <<-JS
      document.body.innerHTML += "<iframe src='/nested_frame_test' name='outer_frame' style='padding:200px'>"
    JS

    sleep 0.5

    inner_frame = page.frame_by(name: "inner_frame")
    log = inner_frame.at_css("#log")
    inner_frame.at_css("#one").click
    expect(log.text).to eq("one")
  end

  it "does not wait forever for the frame to load" do
    page.go_to

    frame = page.frame_by(name: "omg")

    expect(frame).to be_nil
  end

  it "can get the frames url" do
    page.go_to("/frames")

    frame = page.at_xpath("//iframe").frame
    expect(frame.url).to end_with("/slow")
    expect(page.current_url).to end_with("/frames")
  end

  it "can set page content" do
    page.content = "<html><head></head><body>Voila! <a href='#'>Link</a></body></html>"

    expect(page.body).to include("Voila!")
    expect(page.at_css("a").text).to eq("Link")
  end

  it "gets page doctype" do
    page.go_to("/frames")
    expect(page.doctype).to eq("<!DOCTYPE html>")

    doctype40 = %(<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">)
    page.content = "#{doctype40}<html><head></head><body>Voila!</body></html>"
    expect(page.doctype).to eq(doctype40)

    page.content = ""
    expect(page.doctype).to be_nil
  end

  context "#frame_element" do
    it "gets the frame element" do
      page.go_to("/frames")

      frame_element = page.at_xpath("//iframe")
      frame = frame_element.frame
      expect(frame.frame_element).to eq(frame_element)
      expect(frame.frame_element.frame_id).to eq frame.id
      expect(frame.frame_element.attribute(:src)).to end_with("/slow")
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

  context "#xpath" do
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

  context "#at_xpath" do
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
  end

  context "#css" do
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

  context "#at_css" do
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
end

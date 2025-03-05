# frozen_string_literal: true

require "base64"
require "image_size"
require "pdf/reader"
require "chunky_png"
require "ferrum/rgba"

describe Ferrum::Page::Screencast do
  let(:format) { :jpeg }

  after(:example) { browser.stop_screencast }

  describe "#start_screencast" do
    context "when the page has no changing content" do
      it "continues screencasting frames" do
        browser.go_to "/long_page"

        count = 0
        browser.start_screencast(format: format) do |data|
          Base64.decode64(data) # decodable
          count += 1
        end
        sleep 5

        expect(count).to be_between(1, 5)
      ensure
        browser.stop_screencast
      end
    end

    context "when the page content continually changes" do
      it "stops screencasting frames when the page has finished rendering" do
        browser.go_to "/animation"

        count = 0
        browser.start_screencast(format: format) do |data|
          Base64.decode64(data) # decodable
          count += 1
        end
        sleep 5

        expect(count).to be > 250
      ensure
        browser.stop_screencast
      end
    end
  end

  describe "#stop_screencast" do
    context "when the page content continually changes" do
      it "stops screencasting frames when the page has finished rendering" do
        browser.go_to "/animation"

        count = 0
        browser.start_screencast(format: format) do |data|
          Base64.decode64(data)
          count += 1
        end
        sleep 2
        expect(count).to be > 50
        browser.stop_screencast
        sleep 2 # wait for events on the fly to land

        expect { sleep 2 }.not_to(change { count })
      end
    end
  end
end

# frozen_string_literal: true

require 'base64'
require "image_size"
require "pdf/reader"
require "chunky_png"
require "ferrum/rgba"

describe Ferrum::Page::Screencast do
  after(:example) do
    browser.stop_screencast

    Dir.glob("#{PROJECT_ROOT}/spec/tmp/screencast_frame*") { File.delete _1 }
  end

  describe '#start_screencast' do
    context 'when the page has no changing content' do
      it 'should continue screencasting frames' do
        browser.go_to '/ferrum/long_page'

        format = :jpeg
        count = 0
        browser.start_screencast(format: format) do |data, metadata, session_id|
          count += 1
          File.open("#{PROJECT_ROOT}/spec/tmp/screencast_frame_#{'%05d' % count}.#{format}", 'wb') do
            _1.write(Base64.decode64 data)
          end
        end

        sleep 5

        expect(Dir.glob("#{PROJECT_ROOT}/spec/tmp/screencast_frame_*").count).to be_positive.and be < 5

        browser.stop_screencast
      end
    end

    context 'when the page content continually changes' do
      it 'should stop screencasting frames when the page has finished rendering' do
        browser.go_to '/ferrum/animation'

        format = :jpeg
        count = 0
        browser.start_screencast(format: format) do |data, metadata, session_id|
          count += 1
          File.open("#{PROJECT_ROOT}/spec/tmp/screencast_frame_#{'%05d' % count}.#{format}", 'wb') do
            _1.write(Base64.decode64 data)
          end
        end

        sleep 5

        expect(Dir.glob("#{PROJECT_ROOT}/spec/tmp/screencast_frame_*").count).to be > 250

        browser.stop_screencast
      end
    end
  end

  describe '#stop_screencast' do
    context 'when the page content continually changes' do
      it 'should stop screencasting frames when the page has finished rendering' do
        browser.go_to '/ferrum/animation'

        format = :jpeg
        count = 0
        browser.start_screencast(format: format) do |data, metadata, session_id|
          count += 1
          File.open("#{PROJECT_ROOT}/spec/tmp/screencast_frame_#{'%05d' % count}.#{format}", 'wb') do
            _1.write(Base64.decode64 data)
          end
        end

        sleep 5

        browser.stop_screencast

        number_of_frames_after_stop = Dir.glob("#{PROJECT_ROOT}/spec/tmp/screencast_frame_*").count

        sleep 2

        no_more_frames_after_stop = number_of_frames_after_stop == Dir.glob("#{PROJECT_ROOT}/spec/tmp/screencast_frame_*").count

        expect(no_more_frames_after_stop).to be_truthy
      end
    end
  end
end

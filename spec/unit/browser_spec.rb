# # frozen_string_literal: true
#
# require "stringio"
#
# module Ferrum
#   describe Browser do
#     it "logs requests and responses" do
#       logger = StringIO.new
#       browser = Browser.new(logger: logger)
#
#       browser.body
#
#       expect(logger.string).to include("return document.documentElement.outerHTML")
#       expect(logger.string).to include("<html><head></head><body></body></html>")
#     end
#
#     it "shows command line options passed" do
#       browser = Browser.new(browser_options: { "blink-settings" => "imagesEnabled=false" })
#
#       arguments = browser.command("Browser.getBrowserCommandLine")["arguments"]
#
#       expect(arguments).to include("--blink-settings=imagesEnabled=false")
#     end
#   end
# end

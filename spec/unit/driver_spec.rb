# # frozen_string_literal: true
#
# module Ferrum
#   describe Driver do
#     context "with no options" do
#       subject { Driver.new(nil) }
#
#       it "instantiates sucessfully" do
#         expect(subject.options).to eq(extensions: [])
#       end
#     end
#
#     context "with a :timeout option" do
#       subject { Driver.new(nil, timeout: 3) }
#
#       it "starts the server with the provided timeout" do
#         expect(subject.browser.timeout).to eq(3)
#       end
#     end
#
#     context "with a :window_size option" do
#       subject { Driver.new(nil, window_size: [800, 600]) }
#
#       it "creates a client with the desired width and height settings" do
#         expect(subject.browser.process.options["window-size"]).to eq("800,600")
#       end
#     end
#   end
# end

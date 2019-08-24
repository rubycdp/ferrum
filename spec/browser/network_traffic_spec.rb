# context "network traffic" do
#   it "keeps track of network traffic" do
#     browser("/ferrum/with_js")
#     urls = @driver.network_traffic.map(&:url)
#
#     expect(urls.grep(%r{/ferrum/jquery.min.js$}).size).to eq(1)
#     expect(urls.grep(%r{/ferrum/jquery-ui.min.js$}).size).to eq(1)
#     expect(urls.grep(%r{/ferrum/test.js$}).size).to eq(1)
#   end
#
#   it "keeps track of blocked network traffic" do
#     @driver.browser.url_blacklist = ["unwanted"]
#
#     browser "/ferrum/url_blacklist"
#
#     blocked_urls = @driver.network_traffic(:blocked).map(&:url)
#
#     expect(blocked_urls).to include(/unwanted/)
#   end
#
#   it "captures responses" do
#     browser("/ferrum/with_js")
#     request = @driver.network_traffic.last
#
#     expect(request.response.status).to eq(200)
#   end
#
#   it "captures errors" do
#     browser("/ferrum/with_ajax_fail")
#     expect(@session).to have_css("h1", text: "Done")
#     error = @driver.network_traffic.last.error
#
#     expect(error).to be
#   end
#
#   it "keeps a running list between multiple web page views" do
#     browser("/ferrum/with_js")
#     expect(@driver.network_traffic.length).to eq(4)
#
#     browser("/ferrum/with_js")
#     expect(@driver.network_traffic.length).to eq(8)
#   end
#
#   it "gets cleared on restart" do
#     browser("/ferrum/with_js")
#     expect(@driver.network_traffic.length).to eq(4)
#
#     @driver.restart
#
#     browser("/ferrum/with_js")
#     expect(@driver.network_traffic.length).to eq(4)
#   end
#
#   it "gets cleared when being cleared" do
#     browser("/ferrum/with_js")
#     expect(@driver.network_traffic.length).to eq(4)
#
#     @driver.clear_network_traffic
#
#     expect(@driver.network_traffic.length).to eq(0)
#   end
#
#   it "blocked requests get cleared along with network traffic" do
#     @driver.browser.url_blacklist = ["unwanted"]
#
#     browser "/ferrum/url_blacklist"
#
#     expect(@driver.network_traffic(:blocked).length).to eq(3)
#
#     @driver.clear_network_traffic
#
#     expect(@driver.network_traffic(:blocked).length).to eq(0)
#   end
#
#   it "counts network traffic for each loaded resource" do
#     browser("/ferrum/with_js")
#     responses = @driver.network_traffic.map(&:response)
#     resources_size = {
#       %r{/ferrum/jquery.min.js$}    => File.size(PROJECT_ROOT + "/spec/support/public/jquery-1.11.3.min.js"),
#       %r{/ferrum/jquery-ui.min.js$} => File.size(PROJECT_ROOT + "/spec/support/public/jquery-ui-1.11.4.min.js"),
#       %r{/ferrum/test.js$}          => File.size(PROJECT_ROOT + "/spec/support/public/test.js"),
#       %r{/ferrum/with_js$}          => 2329
#     }
#
#     resources_size.each do |resource, size|
#       expect(responses.find { |r| r.url[resource] }.body_size).to eq(size)
#     end
#   end
# end

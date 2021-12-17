# frozen_string_literal: true

module Ferrum
  class Network
    describe Exchange do
      it "captures refused connection errors" do
        page.go_to("/ferrum/with_ajax_connection_refused")
        expect(page.at_xpath("//h1[text() = 'Error']")).to be

        expect(last_exchange.error).to be
        expect(last_exchange.response).to be_nil
        expect(network.idle?).to be true
      end
    end
  end
end

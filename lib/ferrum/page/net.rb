# frozen_string_literal: true

module Ferrum
  class Page
    module Net
      AUTHORIZE_TYPE = %i[server proxy]
      RESOURCE_TYPES = %w[Document Stylesheet Image Media Font Script TextTrack
                          XHR Fetch EventSource WebSocket Manifest
                          SignedExchange Ping CSPViolationReport Other]

      def authorize(user:, password:, type: :server)
        unless AUTHORIZE_TYPE.include?(type)
          raise ArgumentError, ":type should be in #{AUTHORIZE_TYPE}"
        end

        @authorized_ids ||= {}
        @authorized_ids[type] ||= []

        intercept_request

        on(:request_intercepted) do |request, index, total|
          if request.auth_challenge?(type)
            response = authorized_response(@authorized_ids[type],
                                           request.interception_id,
                                           user, password)

            @authorized_ids[type] << request.interception_id
            request.continue(authChallengeResponse: response)
          elsif index + 1 < total
            next # There are other callbacks that can handle this, skip
          else
            request.continue
          end
        end
      end

      def intercept_request(pattern: "*", resource_type: nil)
        pattern = { urlPattern: pattern }
        if resource_type && RESOURCE_TYPES.include?(resource_type.to_s)
          pattern[:resourceType] = resource_type
        end

        command("Network.setRequestInterception", patterns: [pattern])
      end

      private

      def subscribe
        super if defined?(super)

        @client.on("Network.loadingFailed") do |params|
          # Free mutex as we aborted main request we are waiting for
          if params["requestId"] == @request_id && params["canceled"] == true
            @event.set
            @document_id = get_document_id
          end
        end
      end

      def authorized_response(ids, interception_id, username, password)
        if ids.include?(interception_id)
          { response: "CancelAuth" }
        elsif username && password
          { response: "ProvideCredentials",
            username: username,
            password: password }
        else
          { response: "CancelAuth" }
        end
      end
    end
  end
end

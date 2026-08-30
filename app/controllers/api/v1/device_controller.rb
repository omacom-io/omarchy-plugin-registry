module Api
  module V1
    class DeviceController < BaseController
      # Bearer tokens must never land in any cache
      after_action { response.headers["Cache-Control"] = "no-store" }

      # Anonymous endpoints: throttle row creation and polling per IP
      rate_limit to: 10, within: 15.minutes, only: :code, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }
      # 15-minute lifetime at a 5s advisory interval needs up to 180 polls
      rate_limit to: 240, within: 15.minutes, only: :token, store: RATE_LIMIT_STORE,
        with: -> { render json: { error: "slow_down" }, status: :too_many_requests }

      # POST /api/v1/device/code — a device starts the flow, optionally naming
      # the publisher/plugin it wants so the approval page can display the
      # scope instead of making the human re-type it.
      #
      # `scope=client` asks for a token that can rate and comment but never
      # publish; anything else, including nothing, asks for a publish token.
      # verification_uri_complete carries the code in the URL so a desktop app
      # can open a page the user only has to approve — the bare
      # verification_uri stays for a terminal that can only print one.
      def code
        authorization = DeviceAuthorization.start!(
          token_kind: params[:scope] == "client" ? :client : :publish,
          requested_publisher: params[:publisher], requested_plugin: params[:plugin])
        render json: {
          device_code: authorization.plaintext_device_code,
          user_code: authorization.user_code,
          verification_uri: "#{DataPlane.base_url}/device",
          verification_uri_complete: "#{DataPlane.base_url}/device?code=#{authorization.user_code}",
          scope: authorization.token_kind,
          expires_in: DeviceAuthorization::EXPIRATION.to_i,
          interval: DeviceAuthorization::POLL_INTERVAL
        }, status: :created
      end

      # POST /api/v1/device/token — CLI polls until approved
      def token
        authorization = DeviceAuthorization.find_by_device_code(params[:device_code])
        case
        when authorization.nil?
          render json: { error: "expired_token" }, status: :bad_request
        when authorization.pending?
          render json: { error: "authorization_pending", interval: DeviceAuthorization::POLL_INTERVAL }, status: :accepted
        when authorization.denied?
          render json: { error: "access_denied" }, status: :forbidden
        when authorization.claimed?
          render json: { error: "expired_token" }, status: :bad_request
        else
          begin
            plaintext = authorization.claim!
          rescue ActiveRecord::RecordInvalid
            # A concurrent poll won the one-shot claim — same terminal answer
            return render json: { error: "expired_token" }, status: :bad_request
          end
          render json: {
            token: plaintext,
            token_type: "bearer",
            kind: authorization.api_token&.kind,
            scope: authorization.api_token&.scope_label,
            expires_at: authorization.api_token&.expires_at&.utc&.iso8601
          }
        end
      end
    end
  end
end

module Api
  module V1
    # Who the signed-in app is talking as, and how it signs out.
    class MeController < BaseController
      before_action :authenticate_client_token!
      after_action { response.headers["Cache-Control"] = "no-store" }

      # A client calls this right after the device flow, and again on every
      # launch: it is how the app finds out its stored token is still good
      # without having to guess from a failed write.
      def show
        render json: {
          user: {
            name: current_user.name,
            email: current_user.email_address,
            admin: current_user.admin?
          },
          # The namespaces this account publishes under. The browser uses the
          # personal one as the handle behind "My plugins", which is a much
          # better answer than the one it guesses from installed plugin ids.
          publishers: current_user.publishers.map do |publisher|
            { name: publisher.name, kind: publisher.kind,
              personal: publisher.personal?, verified: publisher.verified? }
          end,
          token: {
            hint: current_token.token_hint,
            expires_at: current_token.expires_at.utc.iso8601,
            scope: current_token.scope_label
          }
        }
      end

      # GET /api/v1/me/plugins — what this account publishes, as manifest ids.
      #
      # Membership is the registry's fact and a client cannot derive it from a
      # listing: an org's plugins carry the org's name, not the names of the
      # people in it, so matching a handle against a byline gets an
      # organisation's work wrong in both directions. Asking is the only way
      # to be right.
      #
      # Ids rather than whole entries, because the client already has the
      # listing and only needs to know which rows are yours. That does mean a
      # plugin of yours still in review is not among them — it is not in the
      # public listing to be marked.
      def plugins
        ids = Plugin.where(publisher_id: current_user.publishers.select(:id))
          .includes(:publisher).order(:name).map(&:manifest_id)
        render json: { plugins: ids.sort }
      end

      # Signing out in the app revokes the token rather than only forgetting
      # it. A token the client has thrown away but the registry still honours
      # is exactly the credential nobody notices leaking.
      def destroy
        current_token.revoke!
        head :no_content
      end
    end
  end
end

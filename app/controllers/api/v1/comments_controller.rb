module Api
  module V1
    class CommentsController < BaseController
      include PluginScoped

      before_action :authenticate_client_token!
      before_action :load_plugin!, only: :create
      after_action { response.headers["Cache-Control"] = "no-store" }

      # The same budget the web form gets. A second door onto the same table
      # must not be the cheap way around the first one's limit.
      #
      # Keyed on the account, not the token: signing in again would otherwise
      # reset the budget, and a bearer token has no business being part of a
      # cache key. Declared after the authentication filter so current_user is
      # there to read.
      rate_limit to: 5, within: 1.hour, only: :create, store: RATE_LIMIT_STORE,
        by: -> { current_user&.id },
        with: -> { render json: { error: "slow down — try again in a bit" }, status: :too_many_requests }

      def create
        comment = @plugin.comments.new(user: current_user, body: params[:body])
        if comment.save
          render json: social_payload, status: :created
        else
          render json: { error: comment.errors.full_messages.join("; ") }, status: :unprocessable_entity
        end
      end

      # Authors delete their own comments. Hiding someone else's is moderation
      # and stays in the MFA-gated admin controllers, where it leaves an audit
      # trail — scoping to the user's own comments is what keeps it that way.
      def destroy
        comment = current_user.comments.find(params[:id])
        plugin = comment.plugin
        comment.destroy!
        render json: social_payload(plugin)
      end
    end
  end
end

module Api
  module V1
    class CommentsController < BaseController
      include PluginScoped
      include CommentRateLimit

      before_action :authenticate_client_token!
      # Budget after the plugin, not before it. It is keyed on the account, so
      # it has to come after authentication — but spending a slot on a request
      # that then 404s means a client with a stale id can lose the hour's five
      # without posting anything.
      before_action :load_plugin!, only: :create
      before_action :enforce_comment_budget, only: :create
      after_action { response.headers["Cache-Control"] = "no-store" }

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

      private

      # Literally the same budget as the web form, not a second one that
      # happens to be the same size — see CommentRateLimit.
      def enforce_comment_budget
        return unless comment_budget_exceeded?
        render json: { error: "slow down — try again in a bit" }, status: :too_many_requests
      end
    end
  end
end

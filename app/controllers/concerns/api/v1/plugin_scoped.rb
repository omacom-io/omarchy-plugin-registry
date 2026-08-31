module Api
  module V1
    # Loading a plugin by its "publisher/name" pair, and answering with the
    # social state of it. Shared by every endpoint the desktop browser writes
    # through, so a rating, a comment and a delete all hand back the same
    # shape — the client applies one response and never has to stitch two
    # together or refetch to find out what happened.
    module PluginScoped
      extend ActiveSupport::Concern

      # The same fifty the web page shows. A thread longer than this wants
      # paging, not a bigger number.
      COMMENT_LIMIT = 50

      included do
        rescue_from ActiveRecord::RecordNotFound do
          render json: { error: "not found" }, status: :not_found
        end
      end

      private

      def load_plugin!
        publisher = Publisher.find_by!(name: params[:publisher])
        @plugin = publisher.plugins.find_by!(name: params[:plugin])
        # A plugin that has never been public 404s exactly as a name that
        # never existed does — the same rule the web page follows, so the API
        # is not a way to enumerate what is still in review.
        raise ActiveRecord::RecordNotFound unless @plugin.visible_to?(current_user)
      end

      def social_payload(plugin = @plugin)
        comments = plugin.comments.visible.includes(:user).order(created_at: :desc).limit(COMMENT_LIMIT)
        # One query for the badge rather than a membership lookup per comment.
        member_ids = plugin.publisher.memberships.accepted.pluck(:user_id).to_set

        {
          plugin: plugin.manifest_id,
          # How long the thread actually is, which is not `comments.length`
          # when it has been truncated. A client showing a count next to a
          # card needs the real number, or a plugin with eighty comments
          # starts claiming fifty the moment someone opens it.
          comments_count: plugin.comments_count,
          rating: {
            average: plugin.average_rating,
            count: plugin.ratings_count,
            mine: plugin.ratings.find_by(user: current_user)&.value
          },
          comments: comments.map do |comment|
            {
              id: comment.id,
              body: comment.body,
              created_at: comment.created_at.utc.iso8601,
              # Whether this account can delete it. Authors delete their own;
              # everything else is moderation.
              mine: comment.user_id == current_user.id,
              author: {
                name: comment.user.name,
                publisher_member: member_ids.include?(comment.user_id)
              }
            }
          end
        }
      end
    end
  end
end

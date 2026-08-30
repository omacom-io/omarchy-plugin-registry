module Api
  module V1
    class RatingsController < BaseController
      include PluginScoped

      before_action :authenticate_client_token!
      before_action :load_plugin!
      after_action { response.headers["Cache-Control"] = "no-store" }

      # Idempotent: rating a plugin you have already rated moves your rating
      # rather than failing on the one-per-user constraint, which is what a
      # star control does when you click a different star.
      def update
        value = params[:value].to_i
        unless (1..5).cover?(value)
          return render json: { error: "value must be between 1 and 5" }, status: :unprocessable_entity
        end

        upsert_rating(value)
        render json: social_payload
      end

      # Clearing a rating is not the same as rating something one star, so it
      # gets its own verb rather than a magic value.
      def destroy
        @plugin.ratings.find_by(user: current_user)&.destroy!
        render json: social_payload
      end

      private

      # find-then-write races the one-rating-per-user index: two clicks landing
      # together both see no row and both insert, and the loser gets a 500 for
      # what is a perfectly ordinary request. Losing that race means the row
      # now exists, so the retry finds it and updates — which is the answer
      # either click deserved.
      #
      # Not covered by a test: reaching it means suspending one request between
      # its find and its write, and a test that fakes that convincingly enough
      # to be worth reading has not suggested itself. The web form has the same
      # shape and the same exposure.
      def upsert_rating(value)
        rating = @plugin.ratings.find_or_initialize_by(user: current_user)
        rating.update!(value: value)
      rescue ActiveRecord::RecordNotUnique
        @plugin.ratings.find_by!(user: current_user).update!(value: value)
      end
    end
  end
end

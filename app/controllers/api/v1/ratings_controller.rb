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

        rating = @plugin.ratings.find_or_initialize_by(user: current_user)
        rating.update!(value: value)
        render json: social_payload
      end

      # Clearing a rating is not the same as rating something one star, so it
      # gets its own verb rather than a magic value.
      def destroy
        @plugin.ratings.find_by(user: current_user)&.destroy!
        render json: social_payload
      end
    end
  end
end

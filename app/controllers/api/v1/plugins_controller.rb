module Api
  module V1
    # The viewer's slice of a plugin: the comment thread, and where this
    # account stands on it.
    #
    # The public read of a plugin is the browse API (/plugins/:publisher/:name
    # .json), which is anonymous and cacheable. This is the part that cannot
    # be: it depends on who is asking, so it lives behind a token and is
    # answered no-store.
    class PluginsController < BaseController
      include PluginScoped

      before_action :authenticate_client_token!
      before_action :load_plugin!
      after_action { response.headers["Cache-Control"] = "no-store" }

      def show = render json: social_payload
    end
  end
end

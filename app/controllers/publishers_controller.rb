class PublishersController < ApplicationController
  include ConditionalGet
  include PluginCardData
  allow_unauthenticated_access

  def show
    @publisher = Publisher.find_by!(name: params[:name])
    # includes/with_attached: the shared plugin partial reads publisher and
    # preview for every row, and both formats render it.
    @plugins = @publisher.plugins.directory_visible
      .includes(:publisher).with_attached_preview_card
      .select("plugins.*", "#{PluginCardData::LATEST_SHA_SQL} AS latest_sha256")
      .order(downloads_count: :desc)
    @daily_installs = daily_installs_for(@plugins)
    freshen(@publisher, @plugins)
  end
end

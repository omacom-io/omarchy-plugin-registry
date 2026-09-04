module PluginCardData
  extend ActiveSupport::Concern

  PUBLISHED_STATE = PluginVersion.states.fetch(:published)
  LATEST_SHA_SQL = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, PUBLISHED_STATE ]).freeze
    (SELECT pv.sha256 FROM plugin_versions pv
      WHERE pv.plugin_id = plugins.id AND pv.state = ?
      ORDER BY pv.published_at DESC LIMIT 1)
  SQL
  SPARK_DAYS = 14

  private

  def daily_installs_for(plugins)
    ids = plugins.map(&:id)
    return {} if ids.empty?
    DailyDownload.joins(:plugin_version)
      .where(plugin_versions: { plugin_id: ids })
      .where(date: (SPARK_DAYS - 1).days.ago.to_date..)
      .group("plugin_versions.plugin_id", :date)
      .sum(:count)
  end
end

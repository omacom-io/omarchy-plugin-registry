class DailyDownload < ApplicationRecord
  belongs_to :plugin_version

  def self.record!(version)
    transaction do
      upsert(
        { plugin_version_id: version.id, date: Date.current, count: 1 },
        unique_by: [ :plugin_version_id, :date ],
        on_duplicate: Arel.sql("count = count + 1")
      )
      version.increment!(:downloads_count, touch: false)
      version.plugin.increment!(:downloads_count, touch: false)
    end
  end
end

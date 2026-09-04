class Rating < ApplicationRecord
  belongs_to :plugin
  belongs_to :user

  validates :value, inclusion: { in: 1..5 }
  validates :user_id, uniqueness: { scope: :plugin_id }

  after_commit :refresh_plugin_totals

  private

  def refresh_plugin_totals
    # Recompute under the plugin lock so interleaved raters can't leave the
    # cached totals inconsistent with the rows
    plugin.with_lock do
      plugin.update_columns(
        ratings_count: plugin.ratings.count,
        ratings_sum: plugin.ratings.sum(:value),
        updated_at: Time.current
      )
    end
  end
end

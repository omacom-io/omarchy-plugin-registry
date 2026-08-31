# No anonymous comments — registry accounts only, which alone kills most of
# the moderation tarpit. Reports land in the shared admin queue.
class Comment < ApplicationRecord
  belongs_to :plugin
  belongs_to :user
  has_many :reports, as: :reportable, dependent: :destroy

  validates :body, presence: true, length: { minimum: 3, maximum: 2_000 }

  scope :visible, -> { where(hidden_at: nil) }

  # plugins.comments_count is the count of VISIBLE comments, which a plain
  # counter cache cannot be: hiding is a soft delete, so the cache would keep
  # counting a comment nobody can read and a card would claim a thread longer
  # than the one it opens. Recomputed under the plugin lock instead, the same
  # way Rating keeps its totals honest.
  after_commit :refresh_plugin_comment_count

  def hidden? = hidden_at.present?

  # Comments from the plugin's own publisher get a badge
  def from_publisher? = user.member_of?(plugin.publisher)

  def refresh_plugin_comment_count
    plugin.with_lock do
      # updated_at too — see Rating#refresh_plugin_totals for why a total that
      # moves without touching the row leaves every cached client stale.
      plugin.update_columns(
        comments_count: plugin.comments.visible.count,
        updated_at: Time.current
      )
    end
  end

  def hide!(actor:)
    update!(hidden_at: Time.current)
    AuditEvent.record!(actor:, action: "comment.hide", subject: self,
      metadata: { plugin: plugin.full_name })
  end
end

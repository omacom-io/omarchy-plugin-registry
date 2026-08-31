# plugins.comments_count now counts VISIBLE comments.
#
# It was a counter cache, and hiding a comment is a soft delete, so a hidden
# one went on being counted: a card claimed a thread longer than the one it
# opened. Comment maintains it under the plugin lock now, the way Rating keeps
# its totals honest — this brings the existing rows in line with what the
# column means from here.
class CountOnlyVisibleComments < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE plugins SET comments_count = (
        SELECT COUNT(*) FROM comments
        WHERE comments.plugin_id = plugins.id AND comments.hidden_at IS NULL
      )
    SQL
  end

  # The old meaning was every comment, hidden or not.
  def down
    execute <<~SQL.squish
      UPDATE plugins SET comments_count = (
        SELECT COUNT(*) FROM comments WHERE comments.plugin_id = plugins.id
      )
    SQL
  end
end

# A token that browses is not a token that publishes.
#
# Every api_token so far has been push-only, minted through the device flow
# for `omarchy plugin publish`. The desktop plugin browser needs a token too,
# but only to say who you are and to post a rating or a comment — it must
# never be able to publish, and the publish path must be able to refuse it.
#
# Existing rows are publish tokens, which is what the default encodes.
class AddKindToApiTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :api_tokens, :kind, :integer, default: 0, null: false
    add_column :device_authorizations, :token_kind, :integer, default: 0, null: false
  end
end

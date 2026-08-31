class Current < ActiveSupport::CurrentAttributes
  attribute :session
  # Set directly by the token-authenticated API, which has no cookie session.
  # The browser path leaves it nil and falls through to the session's user, so
  # domain code can read Current.user without caring which door was used.
  attribute :api_user

  def user = api_user || session&.user
end

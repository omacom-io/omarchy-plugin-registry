# One comment budget per account, however they reach the table.
#
# There are two doors onto comments — the form on the plugin page and the
# client API a signed-in app posts through — and Rails' `rate_limit` builds its
# cache key from the controller, so two controllers can never share one budget
# no matter how their limits are declared. Left as two, the account gets five
# an hour on each and ten in total, which is not what either comment said.
#
# So the counting happens by hand against a key that names the account and
# nothing else. By the account rather than the IP, for the reason
# OnboardingController already gives about its own limit: an office full of
# people behind one address must not share a budget. Commenting requires an
# account either way, so there is always one to key on.
module CommentRateLimit
  extend ActiveSupport::Concern

  MAX_PER_WINDOW = 5
  WINDOW = 1.hour

  private

  def comment_budget_exceeded?
    return false unless Current.user
    key = "comment-budget:#{Current.user.id}"
    # A store that counts nothing (the null store in test) reads as under
    # budget, which is the same thing Rails' own rate_limit does.
    count = Rails.cache.increment(key, 1, expires_in: WINDOW)
    count.present? && count > MAX_PER_WINDOW
  end
end

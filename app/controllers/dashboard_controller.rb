class DashboardController < ApplicationController
  # The one-time minted-token reveal must never land in a shared cache
  after_action { response.headers["Cache-Control"] = "no-store" }

  def show
    @user = Current.user
    @publishers = @user.publishers.includes(:plugins)
    @pending_invites = @user.memberships.pending.includes(:publisher)
    @tokens = @user.api_tokens.usable.order(created_at: :desc)
    @trusted_publishers = TrustedPublisher.where(publisher: @publishers).includes(:publisher)
  end
end

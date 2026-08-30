# Browser side of the device flow: enter the code, see what it grants, approve.
#
# Two devices come through here — `omarchy plugin publish` asking for a publish
# token, and the desktop plugin browser asking to sign in — and they are not
# held to the same bar. Minting something that can ship code needs a freshly
# proved second factor. A client token can only do what this very browser
# session can already do without one, so demanding a passkey before you may
# leave a comment would be theatre, and would lock everyone without MFA out of
# the app entirely. The sensitive-change cooldown still applies to both: it
# gates credential-shaped actions, and this is one.
class DeviceController < ApplicationController
  before_action :require_recent_second_factor, only: :approve, unless: :approving_client?
  before_action :require_no_sensitive_cooldown, only: :approve

  def show
    @user_code = params[:code]
    @authorization = DeviceAuthorization.find_by_user_code(@user_code) if @user_code.present?
    if @user_code.present? && @authorization.nil?
      flash.now[:alert] = "That code isn't valid — it may have expired. Re-run the command and try again."
    end
  end

  def approve
    authorization = DeviceAuthorization.find_by_user_code(params[:code])
    return redirect_to device_path, alert: "That code expired — re-run the command." if authorization.nil?

    if params[:decision] == "deny"
      authorization.deny!(user: Current.user)
      return redirect_to dashboard_path, notice: "Denied. The CLI has been told no."
    end

    # Account-wide token: it can publish to any namespace this user belongs to
    # (each publish still enforces membership, MFA, cooldowns, and the review
    # pipeline). Tighter scoping lands later.
    begin
      token = authorization.approve!(user: Current.user)
    rescue ActiveRecord::RecordInvalid => e
      return redirect_to dashboard_path, alert: e.record.errors.full_messages.join("; ")
    end
    AuditEvent.record!(actor: Current.user, action: "device.approve", subject: authorization,
      metadata: { kind: token.kind, scope: token.scope_label })

    notice = if token.client?
      "Signed in — the plugin browser is connected to your account for 30 days."
    else
      "Approved — your terminal has a publish token for your account. It expires in 7 days."
    end
    redirect_to dashboard_path, notice: notice
  end

  private

  # Reads the pending authorization rather than anything the request says, so
  # the weaker gate can only ever be reached by a row that was created asking
  # for a client token.
  def approving_client?
    DeviceAuthorization.find_by_user_code(params[:code])&.for_client? || false
  end
end

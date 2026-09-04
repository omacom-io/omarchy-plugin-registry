require "test_helper"

class DashboardTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
    sign_in_as @user
  end

  test "renders the token list across every scope tier" do
    account = ApiToken.mint!(user: @user)
    namespace = ApiToken.mint!(user: @user, publisher: @publisher)
    plugin = ApiToken.mint!(user: @user, publisher: @publisher, plugin_name: "weather")

    get dashboard_path
    assert_response :success
    assert_match account.scope_label, response.body
    assert_select "td", text: "acme/*"
    assert_select "td", text: "acme/weather"
  end

  test "uses the shared terminal shell with semantic account navigation and aligned actions" do
    get dashboard_path

    assert_response :success
    assert_select "article.terminal-window.terminal-window--ansi.account-terminal[aria-labelledby='dashboard-title']", 1
    assert_select ".terminal-window__titlebar", text: /Account dashboard.*account\/dashboard.*publish ready/m
    assert_select ".terminal-window__titlebar-action[href=?]", settings_two_factor_path, text: /security/, count: 1
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy account status']", 1
    assert_select "nav[aria-label='Account sections'][data-controller='terminal-tree']" do
      assert_select "a", 6
      assert_select "a[data-terminal-tree-target='link'][data-action='terminal-tree#select']", 6
      assert_select "a.is-active[aria-current='location'][href='#overview']", text: /overview/, count: 1
    end
    assert_select "#overview .account-overview__strip", text: /namespaces.*usable tokens.*trusted publishers.*publish ready/m
    assert_select "#namespaces.account-section .account-panel", minimum: 1
    assert_select "#tokens form.account-form--token" do
      assert_select "label[for='publisher_name']", text: "Namespace"
      assert_select ".account-select[data-controller='select-picker'] select#publisher_name[data-action*='select-picker#open']", 1
      assert_select "label[for='plugin_name']", text: "Plugin name"
      assert_select "button.account-button", text: "Mint token"
    end
    assert_select "#trusted form.account-form--trusted" do
      assert_select "label[for]", 5
      assert_select ".account-select[data-controller='select-picker'] select#trusted_publisher_name[data-action*='select-picker#open']", 1
      assert_select "button.account-button", text: "Register"
    end
    assert_select "#organizations a.account-button[href=?]", new_org_path, text: "Create an org"
    assert_select "#session button.account-button", text: "Sign out"
    assert_select ".account-terminal .button:not(.account-button)", count: 0
  end

  test "TOTP setup reuses the labeled detail-page copy control" do
    @user.update!(otp_secret: nil, otp_enabled_at: nil)

    get settings_two_factor_path

    assert_response :success
    assert_select "[data-controller~='clipboard']" do
      assert_select "button.copy-button.copy-button--labeled[data-action='clipboard#copy'][data-copy-default-label='Copy TOTP secret'][data-copy-copied-label='TOTP secret copied']" do
        assert_select ".copy-button__copy-label", text: "copy"
        assert_select ".copy-button__done-label", text: "copied"
      end
    end
  end

  test "organization creation and account security use the same themed shell" do
    get new_org_path

    assert_response :success
    assert_select "article.terminal-window--ansi.account-terminal[aria-labelledby='new-org-title']", 1
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy account org create']", 1
    assert_select "form.account-form--organization" do
      assert_select "label[for='publisher_name']", text: "Namespace"
      assert_select "input#publisher_name[autocomplete='off'][spellcheck='false']"
      assert_select "label[for='publisher_display_name']", text: "Display name"
      assert_select ".account-form__actions .account-button", 2
    end

    get settings_two_factor_path

    assert_response :success
    assert_select "article.terminal-window--ansi.account-terminal[aria-labelledby='security-title']", 1
    assert_select ".terminal-window__prompt[aria-label='Command: omarchy account secure']", 1
    assert_select "nav[aria-label='Account security sections'] a", 3
    assert_select "#passkeys.account-panel"
    assert_select "#authenticator.account-panel"
    assert_select ".account-terminal .button:not(.account-button)", count: 0
  end
end

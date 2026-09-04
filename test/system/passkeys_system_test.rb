require "application_system_test_case"

# End-to-end proof of the browser-critical passkey path: the REAL Stimulus
# controller runs in a real (headless) Chrome against a virtual authenticator —
# JSON serialization, the WebAuthn ceremonies, and redirect handling included.
# (FakeClient integration tests cover server-side verification; this covers the
# JavaScript they bypass.)
class PasskeysSystemTest < ApplicationSystemTestCase
  setup do
    options = Selenium::WebDriver::VirtualAuthenticatorOptions.new(
      protocol: :ctap2, resident_key: true, user_verification: true, user_verified: true
    )
    @authenticator = page.driver.browser.add_virtual_authenticator(options)
    @user = User.create!(email_address: "dev@example.com", name: "Dev")

    # The ceremony origin is the Capybara server, not the configured base URL
    server = Capybara.current_session.server
    @original_origins = WebAuthn.configuration.allowed_origins
    WebAuthn.configuration.allowed_origins = [ "http://#{server.host}:#{server.port}" ]
  end

  teardown do
    @authenticator&.remove!
    WebAuthn.configuration.allowed_origins = @original_origins
  end

  def sign_in_with_email_code
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    click_button "Email me a code"
    assert_text "Enter your code" # wait for the request to complete
    perform_enqueued_jobs
    fill_in "code", with: ActionMailer::Base.deliveries.last.subject[/\b(\d{6})\b/, 1]
    click_button "Sign in"
  end

  test "passkey failures replace ready state in the terminal status block" do
    visit new_session_path
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options) => String(url).includes("/session/passkey/options")
        ? Promise.resolve(new Response("{}", { status: 500, headers: { "Content-Type": "application/json" } }))
        : window.__realFetch(url, options)
    JS

    click_button "Sign in with a passkey"

    assert_selector ".terminal-auth-status__error", text: /\[ error \].*Could not start the passkey ceremony\./m
    assert_no_selector ".terminal-auth-status__ready"
  end

  test "registering a passkey and signing in with it, through the real browser ceremony" do
    sign_in_with_email_code
    assert_text "Claim your namespace"
    fill_in "name", with: "Dev"
    fill_in "handle", with: "dev"
    click_button "Claim it"

    # Registration ceremony via the Stimulus controller
    assert_text "Second factor"
    click_button "Add a passkey"
    assert_text(/last used/i, wait: 10)
    assert_equal 1, @user.passkeys.count
    assert @user.reload.can_publish?

    # Sign out, then the username-less passkey sign-in ceremony
    visit dashboard_path
    click_button "Sign out"
    assert_current_path root_path
    visit new_session_path

    click_button "Sign in with a passkey"
    assert_current_path root_path, wait: 10
    assert_link "account/dashboard →", href: dashboard_path # authenticated header appears
    visit dashboard_path
    assert_text "Hey, Dev"
  end
end

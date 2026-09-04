require "test_helper"

class PasswordlessAuthTest < ActionDispatch::IntegrationTest
  test "signs in with an emailed one-time code and onboards" do
    post session_path, params: { email_address: "new@example.com" }
    assert_redirected_to verify_session_path

    user = User.find_by!(email_address: "new@example.com")
    assert_enqueued_emails 1
    code = emailed_login_code

    get verify_session_path
    assert_response :success
    assert_select "input#code[autofocus][autocomplete='one-time-code']", count: 1

    post authenticate_session_path, params: { code: code }
    assert_redirected_to onboarding_path

    get onboarding_path
    assert_response :success
    assert_select "input#name[autofocus][autocomplete='name']", count: 1

    post onboarding_path, params: { name: "New Dev", handle: "newdev" }
    assert_redirected_to settings_two_factor_path
    assert user.reload.onboarded?
    assert_equal "newdev", user.personal_publisher.name
    assert user.owner_of?(user.personal_publisher)
  end

  test "rejects wrong and reused codes" do
    user = User.create!(email_address: "dev@example.com")
    post session_path, params: { email_address: user.email_address }
    code = emailed_login_code

    post authenticate_session_path, params: { code: "000000" }
    assert_response :unprocessable_entity

    post authenticate_session_path, params: { code: code }
    assert_response :redirect

    delete session_path
    post session_path, params: { email_address: user.email_address }
    post authenticate_session_path, params: { code: code }
    assert_response :unprocessable_entity
  end

  test "rejects expired codes" do
    user = User.create!(email_address: "dev@example.com")
    post session_path, params: { email_address: user.email_address }
    code = emailed_login_code
    user.login_codes.last.update!(created_at: 16.minutes.ago)

    post authenticate_session_path, params: { code: code }
    assert_response :unprocessable_entity
  end

  test "onboarding rejects reserved and taken handles" do
    user = User.create!(email_address: "dev@example.com")
    post session_path, params: { email_address: user.email_address }
    post authenticate_session_path, params: { code: emailed_login_code }

    post onboarding_path, params: { name: "Dev", handle: "omarchy-stuff" }
    assert_response :unprocessable_entity
    assert_not user.reload.onboarded?
  end

  test "unauthenticated dashboard access redirects to sign-in" do
    get dashboard_path
    assert_redirected_to new_session_path
  end
end

require "test_helper"

class DeviceFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    @publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true)
  end

  test "device code entry focuses the required code field" do
    sign_in_as @user

    get device_path

    assert_response :success
    assert_select "input#code[required][autofocus][autocomplete='off']", count: 1
  end

  test "full device flow: code -> approval -> polled token that can publish" do
    post "/api/v1/device/code"
    assert_response :created
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :accepted
    assert_equal "authorization_pending", response.parsed_body["error"]

    sign_in_as @user
    post approve_device_path, params: { code: user_code, publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :success
    token = response.parsed_body["token"]
    assert token.start_with?("omp_")
    assert_match(/account/, response.parsed_body["scope"])

    # Token is single-claim
    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :bad_request

    # And it actually publishes
    post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
    assert_response :created
  end

  test "denial reaches the CLI" do
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]

    sign_in_as @user
    post approve_device_path, params: { code: user_code, decision: "deny" }

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :forbidden
  end

  test "codes expire" do
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    travel_to 16.minutes.from_now do
      post "/api/v1/device/token", params: { device_code: device_code }
      assert_response :bad_request
    end
  end

  test "account-wide token publishes multiple plugins from one approval" do
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]

    sign_in_as @user
    post approve_device_path, params: { code: user_code }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    token = response.parsed_body["token"]
    assert_match(/account/, response.parsed_body["scope"])

    # One token, two different plugins in the namespace — no re-approval
    %w[weather clock].each do |name|
      post "/api/v1/plugins/acme/#{name}/versions",
        params: TarballBuilder.build(manifest: TarballBuilder.manifest("id" => "acme.#{name}", "name" => name)),
        headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
      assert_response :created, "publishing #{name} failed: #{response.body}"
    end
  end

  test "account-wide token cannot reach a namespace the user does not belong to" do
    stranger = Publisher.create!(name: "someone-else", kind: :org)
    post "/api/v1/device/code"
    device_code = response.parsed_body["device_code"]
    user_code = response.parsed_body["user_code"]
    sign_in_as @user
    post approve_device_path, params: { code: user_code }
    post "/api/v1/device/token", params: { device_code: device_code }
    token = response.parsed_body["token"]

    post "/api/v1/plugins/#{stranger.name}/weather/versions", params: TarballBuilder.build,
      headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/gzip" }
    assert_includes [ 403, 404 ], response.status
  end

  test "the requested scope hint is shown as context but does not limit the token" do
    post "/api/v1/device/code", params: { publisher: "acme", plugin: "weather" }
    user_code = response.parsed_body["user_code"]
    sign_in_as @user
    get device_path(code: user_code)
    assert_response :success
    assert_select "p.hint", /acme\/weather/           # context line
    assert_select "input[name=plugin_name]", false    # no plugin field to fat-finger
    assert_select "select[name=publisher_name]", false
  end

  test "a malformed requested scope hint is dropped, not stored" do
    post "/api/v1/device/code", params: { publisher: "Bad Name!", plugin: "../etc" }
    assert_response :created
    auth = DeviceAuthorization.find_by_user_code(response.parsed_body["user_code"])
    assert_nil auth.requested_publisher_name
    assert_nil auth.requested_plugin_name
  end

  test "approval requires MFA" do
    post "/api/v1/device/code"
    user_code = response.parsed_body["user_code"]

    @user.update!(otp_enabled_at: nil)
    sign_in_as @user
    post approve_device_path, params: { code: user_code, publisher_name: "acme", plugin_name: "weather" }
    assert_redirected_to settings_two_factor_path
  end
end

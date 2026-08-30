require "test_helper"

# The API a signed-in desktop plugin browser talks to: sign in through the
# device flow, find out who you are, and write the two things a client can
# write — a rating and a comment.
#
# The line these tests exist to hold is that a client token is not a publish
# token and never becomes one.
class ClientApiTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "kim@example.com", name: "Kim Rivera")
    @acme = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher: @acme, user: @user, role: :owner, founding: true)
    @weather = Plugin.create!(publisher: @acme, name: "weather", summary: "Forecast in the bar",
      latest_version: "1.0.0", kinds: [ "bar-widget" ])
    @weather.versions.create!(version: "1.0.0", manifest: {}, sha256: "0" * 64,
      size_bytes: 1, state: :published, published_at: 1.day.ago)
  end

  def body = response.parsed_body

  def auth(token) = { "Authorization" => "Bearer #{token}" }

  # The whole flow, as the app runs it: ask for a code, open the browser at
  # the URL the response hands back, approve, and poll until a token arrives.
  def sign_in_client(user: @user)
    post "/api/v1/device/code", params: { scope: "client" }
    assert_response :created
    device_code, user_code = body["device_code"], body["user_code"]

    sign_in_as user, second_factor_verified: false
    post approve_device_path, params: { code: user_code }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :success
    body["token"]
  end

  # --- signing in ----------------------------------------------------------

  test "a client signs in through the device flow and gets a client token" do
    post "/api/v1/device/code", params: { scope: "client" }
    assert_response :created
    assert_equal "client", body["scope"]
    # A desktop app can open a page the user only has to approve, rather than
    # making them retype a code it already knows.
    assert_includes body["verification_uri_complete"], body["user_code"]

    device_code, user_code = body["device_code"], body["user_code"]

    sign_in_as @user, second_factor_verified: false
    get device_path(code: user_code)
    assert_response :success
    assert_match(/plugin browser/i, response.body)
    assert_match(/cannot publish/i, response.body)

    post approve_device_path, params: { code: user_code }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :success
    assert_equal "client", body["kind"]
    assert_equal ApiToken::CLIENT_TTL.from_now.to_date.to_s, Date.parse(body["expires_at"]).to_s
  end

  # A publish token can ship code, so it needs a freshly proved second factor.
  # A client token can do nothing this browser session cannot already do
  # without one, and gating it would lock everyone without MFA out of the app.
  test "signing a client in does not demand a second factor" do
    refute @user.second_factor?
    assert sign_in_client.start_with?("omp_")
  end

  test "a publish token still demands a second factor" do
    post "/api/v1/device/code"
    user_code = body["user_code"]

    sign_in_as @user, second_factor_verified: false
    post approve_device_path, params: { code: user_code }
    assert_redirected_to settings_two_factor_path
  end

  # The scope is decided when the row is created, so nothing the approving
  # browser sends can turn a client request into a publish token.
  test "an unknown scope asks for the flow that is gated hardest" do
    post "/api/v1/device/code", params: { scope: "everything" }
    assert_equal "publish", body["scope"]
  end

  test "me reports the account and the namespaces it publishes under" do
    get "/api/v1/me", headers: auth(sign_in_client)
    assert_response :success

    assert_equal "Kim Rivera", body["user"]["name"]
    refute body["user"]["admin"]
    assert_equal [ "acme" ], body["publishers"].map { |p| p["name"] }
    assert_equal "browse, rate and comment as you", body["token"]["scope"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  test "signing out revokes the token rather than only forgetting it" do
    token = sign_in_client

    delete "/api/v1/session", headers: auth(token)
    assert_response :no_content

    get "/api/v1/me", headers: auth(token)
    assert_response :unauthorized
  end

  # --- the boundary between the two kinds -----------------------------------

  test "a client token cannot publish" do
    post "/api/v1/plugins/acme/weather/versions", params: TarballBuilder.build,
      headers: auth(sign_in_client).merge("Content-Type" => "application/gzip")
    assert_response :forbidden
    assert_match(/not a publish token/, body["error"])
  end

  test "a publish token cannot comment" do
    publish_token = ApiToken.mint!(user: @user).plaintext_token

    post "/api/v1/plugins/acme/weather/comments", params: { body: "Nice one" },
      headers: auth(publish_token)
    assert_response :forbidden
    assert_match(/not a client token/, body["error"])
    assert_equal 0, @weather.comments.count
  end

  test "a suspended account loses a live client token" do
    token = sign_in_client
    @user.update!(suspended_at: Time.current)

    get "/api/v1/me", headers: auth(token)
    assert_response :forbidden
    assert_match(/suspended/, body["error"])
  end

  test "no token at all is unauthorized" do
    get "/api/v1/me"
    assert_response :unauthorized
  end

  # --- rating ---------------------------------------------------------------

  test "rating a plugin, moving the rating, and clearing it" do
    token = sign_in_client

    put "/api/v1/plugins/acme/weather/rating", params: { value: 5 }, headers: auth(token)
    assert_response :success
    assert_equal 5, body["rating"]["mine"]
    assert_equal 5.0, body["rating"]["average"]
    assert_equal 1, body["rating"]["count"]

    # Clicking a different star moves the rating rather than failing on the
    # one-per-user constraint.
    put "/api/v1/plugins/acme/weather/rating", params: { value: 3 }, headers: auth(token)
    assert_response :success
    assert_equal 3, body["rating"]["mine"]
    assert_equal 1, body["rating"]["count"]

    delete "/api/v1/plugins/acme/weather/rating", headers: auth(token)
    assert_response :success
    assert_nil body["rating"]["mine"]
    assert_equal 0, body["rating"]["count"]
  end

  test "a rating outside one to five is refused" do
    token = sign_in_client
    [ 0, 6, -1 ].each do |value|
      put "/api/v1/plugins/acme/weather/rating", params: { value: value }, headers: auth(token)
      assert_response :unprocessable_entity
    end
    assert_equal 0, @weather.ratings.count
  end

  # --- comments -------------------------------------------------------------

  test "posting a comment answers with the thread it landed in" do
    token = sign_in_client

    post "/api/v1/plugins/acme/weather/comments", params: { body: "Runs well on two monitors." },
      headers: auth(token)
    assert_response :created

    comment = body["comments"].sole
    assert_equal "Runs well on two monitors.", comment["body"]
    assert_equal "Kim Rivera", comment["author"]["name"]
    # Kim owns acme, so the badge the web page shows is on the API too.
    assert comment["author"]["publisher_member"]
    assert comment["mine"], "the author must be able to see it is theirs"
  end

  test "an empty comment is refused with the reason" do
    post "/api/v1/plugins/acme/weather/comments", params: { body: "  " },
      headers: auth(sign_in_client)
    assert_response :unprocessable_entity
    assert_match(/body/i, body["error"])
  end

  test "authors delete their own comments and nobody else's" do
    mine = sign_in_client
    comment = @weather.comments.create!(user: @user, body: "My own comment")

    stranger = User.create!(email_address: "someone@example.com", name: "Someone")
    theirs = @weather.comments.create!(user: stranger, body: "Someone else's comment")

    delete "/api/v1/comments/#{theirs.id}", headers: auth(mine)
    assert_response :not_found
    assert Comment.exists?(theirs.id), "deleting someone else's comment must not work"

    delete "/api/v1/comments/#{comment.id}", headers: auth(mine)
    assert_response :success
    refute Comment.exists?(comment.id)
    assert_equal [ theirs.id ], body["comments"].map { |c| c["id"] }
  end

  test "a hidden comment is not in the thread" do
    token = sign_in_client
    @weather.comments.create!(user: @user, body: "Visible comment")
    @weather.comments.create!(user: @user, body: "Hidden comment", hidden_at: Time.current)

    get "/api/v1/plugins/acme/weather", headers: auth(token)
    assert_response :success
    assert_equal [ "Visible comment" ], body["comments"].map { |c| c["body"] }
  end

  # The web form allows five comments an hour. A second door onto the same
  # table must not be the cheap way around the first one's limit.
  test "commenting is rate limited" do
    token = sign_in_client

    # Rate limiting counts in Rails.cache, which is a null store in test.
    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      6.times do |i|
        post "/api/v1/plugins/acme/weather/comments", params: { body: "Comment number #{i}" },
          headers: auth(token)
      end
      assert_response :too_many_requests
      assert_equal 5, @weather.comments.count
    ensure
      Rails.cache = original_cache
    end
  end

  # --- what a client may see ------------------------------------------------

  test "a plugin that has never been public is not there to read or write" do
    unreleased = Plugin.create!(publisher: Publisher.create!(name: "quiet", kind: :org),
      name: "secret", summary: "Not out yet", kinds: [ "bar-widget" ])
    assert_not unreleased.ever_public?

    token = sign_in_client
    get "/api/v1/plugins/quiet/secret", headers: auth(token)
    assert_response :not_found

    post "/api/v1/plugins/quiet/secret/comments", params: { body: "Hello there" }, headers: auth(token)
    assert_response :not_found
    assert_equal 0, unreleased.comments.count
  end

  test "an unknown plugin is a plain not found" do
    get "/api/v1/plugins/acme/nothing", headers: auth(sign_in_client)
    assert_response :not_found
  end
end

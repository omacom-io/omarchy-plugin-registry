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

  # Someone who sees a code they did not ask for must be able to say no
  # immediately. Gating the safe direction behind a passkey is backwards.
  test "denying never asks for a second factor" do
    post "/api/v1/device/code"
    device_code, user_code = body["device_code"], body["user_code"]

    sign_in_as @user, second_factor_verified: false
    post approve_device_path, params: { code: user_code, decision: "deny" }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_response :forbidden
    assert_equal "access_denied", body["error"]
  end

  # Nothing is minted for a code that has run out, so demanding a factor first
  # answers the wrong question — and tells someone to go and set up MFA when
  # what actually happened is that their code expired.
  test "an expired code says so rather than demanding a second factor" do
    sign_in_as @user, second_factor_verified: false
    post approve_device_path, params: { code: "ZZZZ-ZZZZ" }
    assert_redirected_to device_path
    assert_match(/expired/i, flash[:alert])
  end

  # An account in the sensitive-change cooldown is exactly the one most likely
  # to be looking at a code it did not ask for. Leaving it unable to refuse
  # until the code expires on its own is the wrong way round.
  test "denying works during the sensitive-change cooldown" do
    post "/api/v1/device/code"
    device_code, user_code = body["device_code"], body["user_code"]

    @user.update!(sensitive_change_at: Time.current)
    assert @user.in_publish_cooldown?

    sign_in_as @user, second_factor_verified: false
    post approve_device_path, params: { code: user_code, decision: "deny" }
    assert_redirected_to dashboard_path

    post "/api/v1/device/token", params: { device_code: device_code }
    assert_equal "access_denied", body["error"]
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

  # An org's plugins carry the org's name, not the names of its members, so a
  # client matching a handle against a byline gets this wrong in both
  # directions. The registry is the only thing that knows.
  test "me/plugins lists what the account publishes, across namespaces" do
    token = sign_in_client
    @acme.plugins.create!(name: "clock", summary: "Ticks", latest_version: "1.0.0", kinds: [ "bar-widget" ])

    # A namespace this account has nothing to do with.
    stranger = Publisher.create!(name: "someone", kind: :personal)
    stranger.plugins.create!(name: "theirs", summary: "Not mine", latest_version: "1.0.0", kinds: [ "bar-widget" ])

    get "/api/v1/me/plugins", headers: auth(token)
    assert_response :success
    assert_equal [ "acme.clock", "acme.weather" ], body["plugins"]
    assert_equal "no-store", response.headers["Cache-Control"]
  end

  # The ids exist to mark rows the client already has. One the directory does
  # not carry is one it can never mark, so answering with it only invites the
  # client to render a row it has nothing for.
  test "me/plugins leaves out a plugin the directory does not show" do
    token = sign_in_client
    @acme.plugins.create!(name: "unreleased", summary: "Still in review",
      latest_version: nil, kinds: [ "bar-widget" ])

    get "/api/v1/me/plugins", headers: auth(token)
    assert_response :success
    assert_equal [ "acme.weather" ], body["plugins"]
  end

  test "me/plugins is empty for an account that publishes nothing" do
    loner = User.create!(email_address: "loner@example.com", name: "Loner")
    token = sign_in_client(user: loner)

    get "/api/v1/me/plugins", headers: auth(token)
    assert_response :success
    assert_equal [], body["plugins"]
  end

  test "me/plugins needs a client token" do
    get "/api/v1/me/plugins"
    assert_response :unauthorized
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

  # The plugin's updated_at is what its ETag and the directory's are cut from,
  # so a write that changes no number must not invalidate a shared cache. A
  # star control re-sends the value it already has freely.
  test "rating a plugin the value it already has changes nothing" do
    token = sign_in_client
    put "/api/v1/plugins/acme/weather/rating", params: { value: 4 }, headers: auth(token)
    assert_response :success
    before = @weather.reload.updated_at

    put "/api/v1/plugins/acme/weather/rating", params: { value: 4 }, headers: auth(token)
    assert_response :success
    assert_equal 4, body["rating"]["mine"]
    assert_equal before, @weather.reload.updated_at,
      "a no-op rating touched the plugin and busted its cache"
  end

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

  test "a hidden comment is neither in the thread nor in the count" do
    token = sign_in_client
    @weather.comments.create!(user: @user, body: "Visible comment")
    hidden = @weather.comments.create!(user: @user, body: "Hidden comment")

    get "/api/v1/plugins/acme/weather", headers: auth(token)
    assert_equal 2, body["comments_count"], "both are visible so far"

    hidden.hide!(actor: @user)

    get "/api/v1/plugins/acme/weather", headers: auth(token)
    assert_response :success
    assert_equal [ "Visible comment" ], body["comments"].map { |c| c["body"] }
    # The count has to follow the thread. A card claiming two next to a thread
    # of one is the same bug read from the other side.
    assert_equal 1, body["comments_count"]
    assert_equal 1, @weather.reload.comments_count
  end

  # The thread is truncated; the count is not. A client showing the array's
  # length would make a busy plugin look quieter every time somebody opened it.
  test "the count is the whole thread, not the page of it that came back" do
    token = sign_in_client
    limit = Api::V1::PluginScoped::COMMENT_LIMIT
    (limit + 3).times { |i| @weather.comments.create!(user: @user, body: "Comment number #{i}") }

    get "/api/v1/plugins/acme/weather", headers: auth(token)
    assert_response :success
    assert_equal limit, body["comments"].length
    assert_equal limit + 3, body["comments_count"]
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

  # "The same budget the web form gets" has to mean the same one, not a second
  # one that happens to be the same size. Rails' rate_limit keys on the
  # controller, so two controllers can never share a budget through it.
  test "the web form and the app draw on one comment budget" do
    token = sign_in_client

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      3.times do |i|
        post "/api/v1/plugins/acme/weather/comments", params: { body: "Through the app #{i}" },
          headers: auth(token)
        assert_response :created
      end

      # The browser session from signing in is still here, so the form is a
      # door the same account can walk through.
      2.times do |i|
        post plugin_comments_path("acme", "weather"), params: { body: "Through the form #{i}" }
        assert_redirected_to plugin_path("acme", "weather")
      end

      # Five all told, from both doors. The sixth is refused whichever one it
      # arrives at.
      post plugin_comments_path("acme", "weather"), params: { body: "One too many" }
      assert_match(/slow down/i, flash[:alert])

      post "/api/v1/plugins/acme/weather/comments", params: { body: "One too many" },
        headers: auth(token)
      assert_response :too_many_requests

      assert_equal 5, @weather.comments.count
    ensure
      Rails.cache = original_cache
    end
  end

  # The budget belongs to the account, not to the credential — otherwise
  # signing in again is the cheap way to reset it.
  test "signing in again does not reset the comment budget" do
    first = sign_in_client
    second = sign_in_client
    refute_equal first, second, "the two sign-ins should be different tokens"

    original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    begin
      3.times do |i|
        post "/api/v1/plugins/acme/weather/comments", params: { body: "First token #{i}" },
          headers: auth(first)
        assert_response :created
      end
      3.times do |i|
        post "/api/v1/plugins/acme/weather/comments", params: { body: "Second token #{i}" },
          headers: auth(second)
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

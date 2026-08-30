require "test_helper"

# The JSON read surfaces a native Omarchy plugin browser reads: the directory,
# a plugin, one version, and a publisher. Same controllers and same data as the
# web pages — these tests exist to keep the two from drifting.
class BrowseApiTest < ActionDispatch::IntegrationTest
  setup do
    @acme = Publisher.create!(name: "acme", kind: :org, display_name: "Acme Co", bio: "We ship widgets.")
    @weather = Plugin.create!(publisher: @acme, name: "weather", summary: "Forecast in the bar",
      latest_version: "1.1.0", downloads_count: 500, category: "widgets", tags: %w[weather],
      kinds: [ "bar-widget" ], readme: "# Weather\n\nIt tells you the weather.",
      repository_url: "https://github.com/acme/weather")
    @v1 = @weather.versions.create!(version: "1.0.0", manifest: { "kinds" => [ "bar-widget" ] },
      sha256: "0" * 64, size_bytes: 1024, state: :published, published_at: 2.months.ago, license: "MIT")
    @v11 = @weather.versions.create!(version: "1.1.0", manifest: { "kinds" => [ "bar-widget" ] },
      sha256: "1" * 64, size_bytes: 2048, state: :published, published_at: 1.day.ago, license: "MIT",
      min_omarchy_version: "3.0.0",
      capability_fingerprint: { "processes" => [ "curl" ], "network" => [ "api.weather.example" ],
                                "paths" => [], "writes" => [], "keybindings" => false })
  end

  def body = JSON.parse(response.body)

  def seed_filler(count)
    count.times do |i|
      plugin = Plugin.create!(publisher: @acme, name: "filler-#{i}", summary: "Filler #{i}",
        latest_version: "1.0.0", kinds: [ "bar-widget" ])
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: format("%064d", i),
        size_bytes: 1, state: :published, published_at: 1.day.ago)
    end
  end

  # --- directory -----------------------------------------------------------

  # The detail response layers a comments ARRAY over the same partial, so the
  # count needs its own name or a client parses a plugin two different ways
  # depending on where it found it.
  test "the count and the thread do not share a key" do
    kim = User.create!(email_address: "kim@example.com", name: "Kim")
    @weather.comments.create!(user: kim, body: "Runs well on two monitors.")

    get plugin_path("acme", "weather", format: :json)
    assert_response :success
    plugin = body["plugin"]
    assert_kind_of Array, plugin["comments"]
    assert_equal 1, plugin["comments_count"]
  end

  test "the comment count on a listing entry follows the thread" do
    @weather.comments.create!(user: User.create!(email_address: "kim@example.com", name: "Kim"),
      body: "Runs well on two monitors.")

    get directory_json_path
    assert_response :success
    assert_equal 1, body["plugins"].sole["comments_count"]
  end

  # A namespace seeded from the legacy marketplace has nobody behind it yet,
  # and a client must be able to say so instead of implying endorsement.
  test "an unclaimed publisher is said so on the listing entry" do
    @acme.update!(claimed: false)

    get directory_json_path
    assert_response :success
    refute body["plugins"].sole["publisher_claimed"]
  end

  test "a verified publisher is said so on the listing entry" do
    @acme.update!(verified: true)

    get directory_json_path
    assert_response :success
    assert body["plugins"].sole["publisher_verified"]
  end

  test "directory JSON lists plugins with the browse vocabulary attached" do
    get directory_json_path
    assert_response :success
    assert_equal "application/json", response.media_type

    assert_equal 1, body["schema_version"]
    entry = body["plugins"].sole
    assert_equal "acme.weather", entry["id"]
    assert_equal "acme/weather", entry["full_name"]
    assert_equal "1.1.0", entry["latest_version"]
    assert_equal "widgets", entry["category"]
    assert_equal "Widgets", entry["category_label"]
    assert_equal "omarchy plugin add acme/weather", entry["install_command"]
    # Counted, not fetched — a grid cannot afford a thread per card.
    assert_equal 0, entry["comments_count"]
    assert_equal "http://registry.test/plugins/acme/weather", entry["url"]

    # The namespace's standing travels with every entry, so a grid can render
    # a trust badge without fetching a publisher per card.
    assert entry["publisher_claimed"]
    refute entry["publisher_verified"]

    # Facets a client would otherwise have to hardcode
    assert_includes body["taxonomy"]["sorts"], "trending"
    assert_includes body["taxonomy"]["tags"], "weather"
    widgets = body["taxonomy"]["categories"].find { |c| c["slug"] == "widgets" }
    assert_equal({ "slug" => "widgets", "label" => "Widgets", "count" => 1 }, widgets)

    assert_equal 1, body["page"]["number"]
    assert_equal 1, body["page"]["total"]
    refute body["page"]["more"]
  end

  test "directory JSON honours the same filters and typed operators as the page" do
    Plugin.create!(publisher: @acme, name: "mixer", summary: "Volume", latest_version: "1.0.0",
      category: "system", kinds: [ "bar-widget" ])
      .versions.create!(version: "1.0.0", manifest: {}, sha256: "2" * 64, size_bytes: 1,
        state: :published, published_at: 1.day.ago)

    get directory_json_path(category: "widgets")
    assert_equal [ "weather" ], body["plugins"].map { |p| p["name"] }
    assert_equal "widgets", body["query"]["category"]

    get directory_json_path(q: "tag:weather")
    assert_equal [ "weather" ], body["plugins"].map { |p| p["name"] }

    get directory_json_path(sort: "name")
    assert_equal %w[mixer weather], body["plugins"].map { |p| p["name"] }
  end

  test "per_page widens the JSON page and is capped" do
    seed_filler(30)

    get directory_json_path
    assert_equal 24, body["plugins"].size, "default page size is unchanged"
    assert_equal 24, body["page"]["per_page"]

    get directory_json_path(per_page: 31)
    assert_equal 31, body["plugins"].size
    assert_equal 31, body["page"]["per_page"]
    refute body["page"]["more"]

    # Above the cap clamps rather than erroring — and never returns everything
    get directory_json_path(per_page: 5000)
    assert_equal HomeController::MAX_PER_PAGE, body["page"]["per_page"]

    # Junk falls back to the default instead of an empty page
    get directory_json_path(per_page: "banana")
    assert_equal 24, body["page"]["per_page"]
    assert_equal 24, body["plugins"].size
  end

  test "paging with per_page covers the catalog exactly once" do
    seed_filler(30)   # 31 listed plugins in total, with @weather

    seen = []
    page = 1
    loop do
      get directory_json_path(per_page: 10, page: page)
      seen.concat(body["plugins"].map { |p| p["id"] })
      break unless body["page"]["more"]
      page += 1
    end

    assert_equal 31, seen.size
    assert_equal seen.uniq.size, seen.size, "a plugin must not repeat across pages"
  end

  test "the HTML grid ignores per_page so its pager cannot snap back" do
    seed_filler(30)

    get root_path(per_page: 100)
    assert_response :success
    assert_select ".plugin-grid .plugin-card", 24
  end

  # --- plugin detail -------------------------------------------------------

  test "plugin JSON carries the readme, versions, and capability label" do
    get plugin_path(@acme.name, @weather.name, format: :json)
    assert_response :success

    plugin = body["plugin"]
    assert_equal "acme/weather", plugin["full_name"]
    assert_match "It tells you the weather", plugin["readme"]
    assert_equal "https://github.com/acme/weather", plugin["repository"]["url"]
    assert_equal "GitHub", plugin["repository"]["label"]

    assert_equal "1.1.0", plugin["latest"]["version"]
    assert_equal 2048, plugin["latest"]["size_bytes"]
    assert_equal "3.0.0", plugin["latest"]["min_omarchy_version"]

    # The privacy-label read, not the raw fingerprint
    caps = plugin["latest"]["capabilities"]
    refute caps["empty"]
    assert_equal [ "Runs", "Connects to" ], caps["rows"].map { |r| r["label"] }
    assert_equal [ "curl" ], caps["rows"].first["items"]

    assert_equal %w[1.1.0 1.0.0], plugin["versions"].map { |v| v["version"] }
    assert_equal "Acme Co", body["publisher"]["display_name"]
    assert_empty plugin["notices"]
  end

  test "a takedown reaches the JSON payload, not just the page" do
    @weather.update!(state: :security_holding)

    get plugin_path(@acme.name, @weather.name, format: :json)
    assert_response :success
    notice = body["plugin"]["notices"].sole
    assert_equal "security_holding", notice["kind"]
    assert_equal "danger", notice["tone"]
    assert_match "permanently retired", notice["body"]
    refute body["plugin"]["installable"]
    assert_nil body["plugin"]["install_command"]
  end

  test "a yanked version is flagged in the version list and the notices" do
    @v1.update!(state: :yanked, yanked_at: Time.current, yank_reason: "bad build")

    get plugin_path(@acme.name, @weather.name, format: :json)
    yanked = body["plugin"]["versions"].find { |v| v["version"] == "1.0.0" }
    assert yanked["yanked"]
    assert_equal "bad build", yanked["yank_reason"]
    assert_equal "yanked_versions", body["plugin"]["notices"].sole["kind"]
  end

  # --- single version ------------------------------------------------------

  test "a dotted version resolves as JSON instead of being read as a filename" do
    get plugin_version_path(@acme.name, @weather.name, "1.1.0", format: :json)
    assert_response :success
    assert_equal "1.1.0", body["version"]["version"]
    assert body["version"]["latest"]

    # The HTML route still works unchanged
    get plugin_version_path(@acme.name, @weather.name, "1.1.0")
    assert_response :success
  end

  test "a dotted prerelease version survives the format split too" do
    rc = @weather.versions.create!(version: "2.0.0-rc.1", manifest: {}, sha256: "3" * 64,
      size_bytes: 1, state: :published, published_at: 1.hour.ago)
    # What refresh_latest_version! does after a real release
    @weather.update!(latest_version: rc.version)

    get plugin_version_path(@acme.name, @weather.name, rc.version, format: :json)
    assert_response :success
    assert_equal "2.0.0-rc.1", body["version"]["version"]

    # An older version reports itself as not-latest so a client can offer the upgrade
    get plugin_version_path(@acme.name, @weather.name, "1.0.0", format: :json)
    assert_equal "1.0.0", body["version"]["version"]
    refute body["version"]["latest"]
    assert_equal "2.0.0-rc.1", body["plugin"]["latest_version"]
  end

  # --- publisher -----------------------------------------------------------

  test "publisher JSON lists the namespace and its plugins" do
    get publisher_path(@acme.name, format: :json)
    assert_response :success
    assert_equal "Acme Co", body["publisher"]["display_name"]
    assert_equal 1, body["publisher"]["plugin_count"]
    assert_equal [ "acme.weather" ], body["plugins"].map { |p| p["id"] }
  end

  # --- visibility ----------------------------------------------------------

  test "an unreleased plugin 404s as JSON for the public, exactly like the page" do
    hidden = Plugin.create!(publisher: @acme, name: "secret", summary: "wip", kinds: [])
    hidden.versions.create!(version: "0.1.0", manifest: {}, sha256: "4" * 64, size_bytes: 1,
      state: :processing)

    get plugin_path(@acme.name, "secret", format: :json)
    assert_response :not_found
  end

  # --- caching -------------------------------------------------------------

  test "anonymous JSON is publicly cacheable and answers a conditional GET" do
    get plugin_path(@acme.name, @weather.name, format: :json)
    assert_response :success
    assert_includes response.headers["Cache-Control"], "public"
    etag = response.headers["ETag"]
    assert etag.present?

    get plugin_path(@acme.name, @weather.name, format: :json), headers: { "If-None-Match" => etag }
    assert_response :not_modified
  end

  test "a signed-in JSON response is never marked publicly cacheable" do
    user = User.create!(email_address: "member@example.com", name: "Member")
    sign_in_as(user)

    get plugin_path(@acme.name, @weather.name, format: :json)
    assert_response :success
    assert_includes response.headers["Cache-Control"], "private"
    assert_equal false, body["viewer"]["privileged"]
  end

  test "HTML is never marked publicly cacheable — it carries a session cookie" do
    get plugin_path(@acme.name, @weather.name)
    assert_response :success
    assert_not_includes response.headers["Cache-Control"].to_s, "public"
  end

  # --- clients -------------------------------------------------------------

  test "a non-browser client is not turned away by the modern-browser gate" do
    get directory_json_path, headers: { "User-Agent" => "omarchy-plugin/1.0" }
    assert_response :success

    get plugin_path(@acme.name, @weather.name, format: :json),
      headers: { "User-Agent" => "omarchy-plugin/1.0" }
    assert_response :success
  end
end

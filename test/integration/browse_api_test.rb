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

  test "directory JSON does not execute the HTML-only Most Wanted ranking" do
    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get directory_json_path
    end

    assert_response :success
    assert statements.none? { |sql| sql.include?("AS week_downloads") }
  end

  test "directory JSON lists plugins with the browse vocabulary attached" do
    get directory_json_path
    assert_response :success
    assert_equal "application/json", response.media_type

    assert_equal 1, body["schema_version"]
    assert_match(/\A[a-f0-9]{64}\z/, body["catalog_revision"])
    entry = body["plugins"].sole
    assert_equal "acme.weather", entry["id"]
    assert_equal "acme/weather", entry["full_name"]
    assert_equal "1.1.0", entry["latest_version"]
    assert_equal "widgets", entry["category"]
    assert_equal "Widgets", entry["category_label"]
    assert_equal "omarchy plugin add acme/weather", entry["install_command"]
    assert_equal "http://registry.test/plugins/acme/weather", entry["url"]
    assert_equal({ "type" => "sorted", "value" => "downloads" }, entry["match"])
    assert_equal({ "new" => false, "upvotes" => 0, "views" => 0, "verified" => true, "size_bytes" => 2048 },
      entry["card"])
    assert_equal({ "parse" => "none", "scope" => "directory", "match" => "sorted" }, body["plan"])
    assert_empty body["suggestions"]

    # Facets a client would otherwise have to hardcode
    assert_includes body["taxonomy"]["sorts"], "trending"
    assert_includes body["taxonomy"]["search_operators"], "plugin:"
    assert_includes body["taxonomy"]["search_operators"], "text:"
    assert_includes body["taxonomy"]["tags"], "weather"
    categories = body["taxonomy"]["categories"].index_by { |category| category["slug"] }
    assert_equal({ "slug" => "widgets", "label" => "Widgets", "count" => 1, "match_count" => 0 },
      categories["widgets"])
    assert_equal "Development", categories["developer-tools"]["label"]
    assert_equal({ "slug" => "kids", "label" => "Kids", "count" => 0, "match_count" => 0 },
      categories["kids"])
    assert_equal({ "security" => 0 }, body["taxonomy"]["tag_counts"])

    assert_equal 1, body["page"]["number"]
    assert_equal 1, body["page"]["total"]
    refute body["page"]["more"]
  end

  test "Security facet counts distinct directory-visible plugins only" do
    visible = Plugin.create!(publisher: @acme, name: "secure", summary: "Security",
      latest_version: "1.0.0", tags: %w[security security])
    visible.versions.create!(version: "1.0.0", manifest: {}, sha256: "9" * 64,
      size_bytes: 1, state: :published, published_at: 1.day.ago)
    Plugin.create!(publisher: @acme, name: "unreleased-secure", summary: "Hidden", tags: [ "security" ])
    Plugin.create!(publisher: @acme, name: "held-secure", summary: "Held",
      latest_version: "1.0.0", tags: [ "security" ], state: :security_holding)

    get directory_json_path
    assert_equal 1, body.dig("taxonomy", "tag_counts", "security")

    get root_path
    assert_select "a.index-picker__tag[data-tag='security']", text: /security 1/i, count: 1
  end

  test "directory JSON honours the same filters and typed operators as the page" do
    Plugin.create!(publisher: @acme, name: "mixer", summary: "Volume", latest_version: "1.0.0",
      category: "system", kinds: [ "bar-widget" ])
      .versions.create!(version: "1.0.0", manifest: {}, sha256: "2" * 64, size_bytes: 1,
        state: :published, published_at: 1.day.ago)
    Plugin.create!(publisher: @acme, name: "legacy", summary: "Uncategorized", latest_version: "1.0.0")
      .versions.create!(version: "1.0.0", manifest: {}, sha256: "3" * 64, size_bytes: 1,
        state: :published, published_at: 1.day.ago)

    get directory_json_path(category: "widgets")
    assert_equal [ "weather" ], body["plugins"].map { |p| p["name"] }
    assert_equal "widgets", body["query"]["category"]

    get directory_json_path(q: "tag:weather")
    assert_equal [ "weather" ], body["plugins"].map { |p| p["name"] }
    assert_equal({ "parse" => "operator:tag", "scope" => "taxonomy tags", "match" => "exact tag" }, body["plan"])
    assert_equal({ "type" => "tag", "value" => "weather" }, body["plugins"].sole["match"])
    categories = body["taxonomy"]["categories"].index_by { |entry| entry["slug"] }
    assert_equal 1, categories["widgets"]["match_count"]
    assert_equal 0, categories["system"]["match_count"]

    get directory_json_path(q: "wea")
    assert_equal "weather", body["suggestions"].find { |suggestion| suggestion["type"] == "plugin" }["completion"]
    assert_equal({ "parse" => "plain term", "scope" => "name + normalized + summary",
                   "match" => "joined phrase substring" }, body["plan"])

    get directory_json_path(q: "tag:weather wea")
    assert_empty body["suggestions"], "mixed drafts stay on the canonical query path instead of suggesting an unscoped completion"

    get directory_json_path(q: "plugin:weather")
    assert_equal [ "weather" ], body["plugins"].map { |p| p["name"] }

    get directory_json_path(q: "category:system", category: "widgets")
    assert_empty body["plugins"]

    [ "category:other", "other" ].each do |query|
      get directory_json_path(q: query)
      assert_equal [ "legacy" ], body["plugins"].map { |plugin| plugin["name"] }, query
      assert_equal({ "type" => "category", "value" => "other" }, body["plugins"].sole["match"])
    end

    get directory_json_path(q: "othr")
    legacy_match = body["plugins"].find { |plugin| plugin["name"] == "legacy" }
    assert legacy_match, "fuzzy category search should include uncategorized plugins"
    assert_equal({ "type" => "category", "value" => "other" }, legacy_match["match"])

    get directory_json_path(q: "text:volume")
    assert_equal [ "mixer" ], body["plugins"].map { |p| p["name"] }

    get directory_json_path(sort: "name")
    assert_equal %w[legacy mixer weather], body["plugins"].map { |p| p["name"] }
  end

  test "taxonomy suggestions bind and escape JSON candidate queries" do
    get directory_json_path(q: "kind:bar")
    assert_equal "kind:bar-widget", body["suggestions"].find { |entry| entry["type"] == "kind" }["completion"]

    get directory_json_path(q: "tag:wea")
    assert_equal "tag:weather", body["suggestions"].find { |entry| entry["type"] == "tag" }["completion"]

    [ "kind:%", "kind:_", "kind:\\", 'kind:"', "tag:%", "tag:_", "tag:\\", 'tag:"' ].each do |query|
      get directory_json_path(q: query)
      assert_empty body["suggestions"], query
    end
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

    revisions = (1..4).map do |number|
      get directory_json_path(per_page: 10, page: number)
      body["catalog_revision"]
    end
    assert_equal 1, revisions.uniq.size, "every page in an unchanged catalog must identify the same snapshot"
  end

  test "catalog revision changes when plugin card data changes" do
    get directory_json_path
    revision = body["catalog_revision"]

    @weather.update!(summary: "A changed forecast summary")
    get directory_json_path

    refute_equal revision, body["catalog_revision"]
    revision = body["catalog_revision"]

    @weather.increment!(:downloads_count, touch: false)
    get directory_json_path

    refute_equal revision, body["catalog_revision"], "counter writes without updated_at must invalidate catalog snapshots"
  end

  test "trending revisions bind daily downloads and the rolling window" do
    get directory_json_path(sort: "trending")
    revision = body["catalog_revision"]

    DailyDownload.record!(@v11)
    get directory_json_path(sort: "trending")
    refute_equal revision, body["catalog_revision"]
    assert_equal 1, DailyDownload.find_by!(plugin_version: @v11, date: Date.current).count
    assert_equal 501, @weather.reload.downloads_count
    assert_equal 1, @v11.reload.downloads_count

    revision = body["catalog_revision"]
    travel 1.day do
      get directory_json_path(sort: "trending")
      refute_equal revision, body["catalog_revision"], "the seven-day ordering window must identify its date"
    end
  end

  test "catalog revision remains constant-space for large catalogs" do
    now = Time.current
    rows = (1..HomeController::MAX_PER_PAGE * 51).map do |index|
      {
        publisher_id: @acme.id, name: "large-#{index}", normalized_name: "large#{index}",
        latest_version: "1.0.0", state: Plugin.states.fetch(:active), created_at: now, updated_at: now
      }
    end
    rows.each_slice(500) { |batch| Plugin.insert_all!(batch) }

    statements = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      statements << payload[:sql] unless payload[:name] == "SCHEMA"
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get directory_json_path(per_page: HomeController::MAX_PER_PAGE)
    end

    assert_response :success
    assert_operator body.dig("page", "total"), :>, 5000
    assert_equal HomeController::MAX_PER_PAGE, body["plugins"].size
    assert statements.any? { |sql| sql.include?("COUNT(*)") && sql.include?("SUM(plugins.downloads_count)") }
    assert statements.none? { |sql| sql.match?(/SELECT .*plugins.*id.*plugins.*updated_at/i) },
      "revision must not pluck and materialize every matching plugin"
  end

  test "legacy descriptions are safely bounded without invalidating the complete directory response" do
    legacy_summary = "legacy line\n" + ("x" * (Registry::ManifestValidator::MAX_DESCRIPTION_LENGTH + 100))
    @weather.update_column(:summary, legacy_summary)

    get directory_json_path

    assert_response :success
    summary = body["plugins"].sole["summary"]
    assert_equal Registry::ManifestValidator::MAX_DESCRIPTION_LENGTH, summary.each_char.count
    assert_includes summary, "\n"

    get root_path
    assert_response :success
    assert_select ".index-picker__row[data-summary]", 1 do |rows|
      assert_equal Registry::ManifestValidator::MAX_DESCRIPTION_LENGTH, rows.first["data-summary"].each_char.count
    end
  end

  test "the HTML browser stays at nine cards when a client per_page is supplied" do
    seed_filler(30)

    get root_path(per_page: 100)
    assert_response :success
    assert_select ".index-picker__row", HomeController::PER_PAGE
    assert_select ".index-picker__row > a.index-picker__card-open[href]", HomeController::PER_PAGE
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

  test "publisher cards expose a real detail link before JavaScript enhancement" do
    get publisher_path(@acme.name)

    assert_response :success
    assert_select "article.plugin-card:not([tabindex])", 1
    assert_select "a.plugin-card__title-link[href=?]", plugin_path(@acme.name, @weather.name), text: @weather.name
    assert_select "button.plugin-card__flip[aria-expanded='false'][aria-controls=?]", "plugin-card-back-#{@weather.id}", 1
    assert_select "#plugin-card-back-#{@weather.id}[aria-hidden='true'][inert]", 1 do
      assert_select "button.plugin-card__back-toggle[data-action='card-flip#toggleButton']", text: /front/, count: 1
    end
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

  test "directory ETag changes when an off-page category count changes" do
    off_page = Plugin.create!(publisher: @acme, name: "zeta", summary: "Off page",
      latest_version: "1.0.0", category: "system", kinds: [ "bar-widget" ])
    off_page.versions.create!(version: "1.0.0", manifest: {}, sha256: "9" * 64,
      size_bytes: 1, state: :published, published_at: 2.months.ago)

    get directory_json_path(per_page: 1, sort: "name")
    assert_response :success
    etag = response.headers.fetch("ETag")
    assert_nil response.headers["Last-Modified"], "aggregate directory responses are ETag-only"
    system_count = body.dig("taxonomy", "categories").find { |row| row["slug"] == "system" }.fetch("count")
    assert_equal 1, system_count

    # Keep row cache keys, cards, totals, and stats unchanged: only the rendered
    # off-page facet maps should invalidate this directory response.
    off_page.update_columns(category: "other")
    get directory_json_path(per_page: 1, sort: "name"), headers: { "If-None-Match" => etag }

    assert_response :success
    refute_equal etag, response.headers["ETag"]
    system_count = body.dig("taxonomy", "categories").find { |row| row["slug"] == "system" }.fetch("count")
    assert_equal 0, system_count

    get directory_json_path(per_page: 1, sort: "name"),
      headers: { "If-Modified-Since" => 1.year.from_now.httpdate }
    assert_response :success
    assert_nil response.headers["Last-Modified"]
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

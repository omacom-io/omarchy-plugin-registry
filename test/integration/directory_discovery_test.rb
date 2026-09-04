require "test_helper"

# Category/tag filtering, marketplace-compatible operators, match reasons,
# category highlights, and sort modes.
class DirectoryDiscoveryTest < ActionDispatch::IntegrationTest
  setup do
    @acme = Publisher.create!(name: "acme", kind: :org)
    @rival = Publisher.create!(name: "rival", kind: :org)

    @weather = create_published(publisher: @acme, name: "weather", category: "widgets",
      tags: %w[weather bar], summary: "Forecast in the bar", downloads: 500, first_at: 2.months.ago, last_at: 2.months.ago)
    @mixer = create_published(publisher: @acme, name: "mixer", category: "system",
      tags: %w[audio], summary: "Volume control", downloads: 100, first_at: 3.months.ago, last_at: 2.days.ago)
    @fresh = create_published(publisher: @rival, name: "fresh", category: "widgets",
      tags: %w[clock], summary: "Brand new clock", downloads: 5, first_at: 1.day.ago, last_at: 1.day.ago)
  end

  def create_published(publisher:, name:, category:, tags:, summary:, downloads:, first_at:, last_at:)
    plugin = Plugin.create!(publisher:, name:, summary:, latest_version: "1.1.0",
      downloads_count: downloads, category:, tags:, kinds: [ "bar-widget" ])
    plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "0" * 64, size_bytes: 1,
      state: :published, published_at: first_at)
    plugin.versions.create!(version: "1.1.0", manifest: {}, sha256: "1" * 64, size_bytes: 1,
      state: :published, published_at: last_at)
    plugin
  end

  test "hero exposes the complete tree command before enhancement" do
    get root_path

    assert_response :success
    assert_select "section.hero.hero--reveal[data-controller~='hero-reveal']", count: 1 do
      assert_select ".hero__command[translate='no']", count: 1 do
        assert_select ".visually-hidden", text: "registry@omarchy:~$ tree registry/", count: 1
        assert_select ".hero__command-visual[aria-hidden='true']", count: 1 do
          assert_select ".hero__command-host", text: "registry@omarchy", count: 1
          assert_select ".hero__command-text", text: "tree registry/", count: 1
          assert_select ".hero__command-cursor:empty", count: 1
        end
      end
      assert_select "svg.hero__wm[viewBox='0 0 4131 950'][preserveAspectRatio='none'][shape-rendering='crispEdges']", count: 1 do
        assert_select "rect", minimum: 100
      end
    end
    assert_select ".hero__copy > .lab", text: /signed public index/i, count: 0
  end

  test "hero reports the latest publication in compact UTC" do
    published_at = Time.new(2036, 8, 28, 1, 35, 42, "+09:00")
    @fresh.versions.order(:id).last.update!(published_at:)

    get root_path

    assert_response :success
    assert_select ".fetch__rprompt", text: "updated 27 aug 36 · 16:35 UTC" do
      assert_select "time[datetime='2036-08-27T16:35:42Z']", text: "27 aug 36 · 16:35 UTC", count: 1
    end
  end

  test "mobile navigation exposes progressive top-level and Browse links" do
    get root_path

    assert_response :success
    assert_select "nav.mobile-nav[aria-label='Mobile navigation'][data-controller='terminal-tree']", count: 1 do
      assert_select "a.mobile-nav__link", count: 4
      assert_select "a.is-active[href='/#main-content'][aria-current='page'][data-terminal-tree-target='link']", text: "Home", count: 1
      assert_select "a[href='/#browse'][data-terminal-tree-target='link']", text: "Browse", count: 1
      assert_select "a[href=?]", governance_path, text: "Governance", count: 1
      assert_select "a[href=?]", publishing_path, text: "Publish", count: 1
      assert_select "svg[aria-hidden='true']", count: 4
    end
  end

  test "category filter opens a browse context with nine card slots" do
    get root_path(category: "widgets")
    assert_response :success
    assert_select "meta[name='view-transition']", count: 0
    assert_select ".index-picker__row", text: /weather/, count: 1
    assert_select ".index-picker__row", text: /fresh/, count: 1
    assert_select ".index-picker__row", text: /mixer/, count: 0
    assert_select ".index-console[data-controller~='index-picker']", 1
    assert_select ".index-browse__title + .index-search + .index-browse-stack", count: 1
    assert_select ".index-search > form.index-search__form" do
      assert_select "input[role='combobox'][aria-controls='search-suggestions plugin-results'][aria-autocomplete='both'][aria-expanded='false']", 1
      assert_select ".index-search__result[role='status'][aria-live='polite'][data-index-picker-target='searchMatchCount'][hidden]", count: 1
      assert_select ".index-search__reset", text: "reset", count: 1
      assert_select "kbd", text: "/ · ctrl k", count: 1
      assert_select "button.index-search__filter-toggle[hidden][aria-controls='browse-filters'][aria-expanded='false']",
        text: /filter/i, count: 1
    end
    assert_select ".index-query-plan", 0
    assert_select ".fetch__metric[aria-label='3 registry plugins'] .fetch__head", text: /3.*plugins/i, count: 1
    assert_select ".fetch__metric .fetch__rule:empty", count: 1
    assert_select ".fetch__row[data-value='1']", text: /new \/ 14d.*1/i, count: 1
    assert_select ".index-search > header", count: 0
    assert_select ".index-search:not(.is-active) .index-search__examples", count: 1
    assert_select "input[aria-keyshortcuts^='/ Control+K']", 1
    assert_select ".index-console", text: /level 0|independent input/i, count: 0
    assert_select ".index-search:not(.is-active)", 1
    assert_select ".index-browse-layer", 0
    assert_select "#browse-filters [data-index-picker-target='visibleCategories'] a[href]", minimum: 1
    assert_select ".index-console--has-context [data-index-picker-target='visibleCategories']", text: /kids 0.*system 1.*widgets 2/i, count: 1 do
      assert_select "a.index-picker__category", count: 3
      assert_select "a.index-picker__category.is-active[data-category='widgets'][href=?][aria-label='Clear widgets category filter, 2 registry plugins'][data-action='click->index-picker#toggleCategory']",
        root_path, count: 1
    end
    assert_select ".index-picker__row", 2
    assert_select ".index-browse__range[data-index-picker-target='resultRange']", text: /1–2.*\/.*2/m, count: 1
    assert_select ".index-picker__card", HomeController::PER_PAGE
    assert_select ".index-picker__card-head", count: 0
    assert_select ".index-picker__card-artifact", text: /verified.*\S+.*v\S+/i
    assert_select "footer.index-picker__status", text: /nav.*home/i, count: 1
    assert_select ".index-picker__browse-all", count: 0
    assert_select "a.index-picker__home[data-action='index-picker#firstPage']", count: 1 do |links|
      assert_equal root_path(category: "widgets"), links.first["href"]
    end
    assert_select ".index-browse__title", text: /nine cards|one level at a time/, count: 0
    assert_select ".index-browse__rule[aria-hidden='true']", 1
    assert_select "details.index-browse__sort:not([open]) > summary[data-action='click->index-picker#toggleSortDisclosure']", text: /\$ sort -k.*→/, count: 1
    assert_select ".index-browse__sort-options a", count: HomeController::SORTS.size

    get root_path(q: "definitely-absent", sort: "name", category: "widgets", tag: "clock")
    assert_select ".index-picker__row", 0
    assert_select "[data-index-picker-target='breadcrumb']",
      text: /all.*query:definitely-absent.*category:widgets.*tag:clock.*results/m, count: 1
    assert_select "a.index-picker__category.is-active[data-category='widgets'][href=?]",
      root_path(q: "definitely-absent", sort: "name", tag: "clock"), text: /widgets 2/, count: 1
  end

  test "a category filter exposes its complete result set across nine-card pages" do
    8.times do |index|
      create_published(publisher: @acme, name: "widget-#{index}", category: "widgets",
        tags: [], summary: "Widget #{index}", downloads: index,
        first_at: 3.months.ago, last_at: 3.months.ago)
    end

    get root_path(category: "widgets", sort: "name")
    assert_select ".index-picker__row", count: HomeController::PER_PAGE
    assert_select "[data-index-picker-target='visibleCategories']", text: /kids 0.*system 1.*widgets 10/i
    assert_select ".index-browse__range", text: /1–9.*\/.*10/m
    assert_select "a[data-index-picker-target='next'][href=?]",
      root_path(category: "widgets", sort: "name", page: 2), count: 1

    get root_path(category: "widgets", sort: "name", page: 2)
    assert_select ".index-picker__row", count: 1
    assert_select "[data-index-picker-target='visibleCategories']", text: /kids 0.*system 1.*widgets 10/i
    assert_select ".index-browse__range", text: /10–10.*\/.*10/m
  end

  test "the other category includes legacy plugins without a category" do
    uncategorized = create_published(publisher: @acme, name: "legacy", category: nil,
      tags: [], summary: "Legacy plugin", downloads: 0,
      first_at: 3.months.ago, last_at: 3.months.ago)

    get root_path(category: "other", sort: "name")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, uncategorized.name), count: 1
    assert_select ".index-browse__range", text: /1–1.*\/.*1/m

    get root_path(q: "category:other", sort: "name")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, uncategorized.name), count: 1
  end

  test "tag filter narrows to tagged plugins" do
    get root_path(tag: "audio")
    assert_select ".index-picker__row", text: /mixer/, count: 1
    assert_select ".index-picker__row", text: /weather/, count: 0
  end

  test "typed operators: plugin:, text:, @publisher, tag:, kind:, category:" do
    get root_path(q: "plugin:weather")
    assert_select ".index-picker__row", text: /weather/, count: 1
    assert_select ".index-picker__row", text: /mixer/, count: 0
    assert_select ".index-picker__card-title", text: "weather" do
      assert_select "a.index-picker__card-name[href=?][data-action*='sharePlugin'][data-share-label=?]",
        plugin_path(@acme.name, @weather.name), "Copy link to #{@weather.full_name}", count: 1
    end
    assert_select ".index-picker__row[data-url=?] > a.index-picker__card-open[href=?]",
      plugin_path(@acme.name, @weather.name), plugin_path(@acme.name, @weather.name), count: 1
    assert_select ".index-picker__card-signals:not([aria-label])", text: /↓ 500.*0.*0/, count: 1 do
      assert_select ".visually-hidden", text: "500 downloads, 0 upvotes, 0 views", count: 1
      assert_select "svg.index-picker__upvote-glyph path", count: 1
      assert_select "svg.index-picker__view-glyph path + circle", count: 1
    end
    assert_select ".index-picker__card-publisher", text: "acme"
    assert_select ".index-picker__card-artifact", text: /verified.*1 B.*v1\.1\.0/i
    assert_select ".index-picker__card-foot", text: /plugin:name/, count: 0

    get root_path(q: 'text:"volume control"')
    assert_select ".index-picker__row", text: /mixer/, count: 1
    assert_select ".index-picker__row", text: /weather/, count: 0
    assert_select ".index-picker__card-foot", text: /text:volume control/, count: 0

    get root_path(q: "@rival")
    assert_select ".index-picker__row", text: /fresh/, count: 1
    assert_select ".index-picker__row", text: /weather/, count: 0

    get root_path(q: "@acme")
    assert_select ".index-picker__row", text: /weather/, count: 1
    assert_select ".index-picker__row", text: /mixer/, count: 1
    assert_select ".index-picker__row", text: /fresh/, count: 0

    get root_path(q: "tag:bar")
    assert_select ".index-picker__row", text: /weather/, count: 1
    assert_select ".index-picker__row", text: /mixer/, count: 0

    get root_path(q: "category:system")
    assert_select ".index-picker__row", text: /mixer/, count: 1
    assert_select ".index-picker__row", text: /fresh/, count: 0

    get root_path(q: "kind:bar-widget clock")
    assert_select ".index-picker__row", text: /fresh/, count: 1
    assert_select ".index-picker__row", text: /weather/, count: 0
    assert_select ".index-search__result", text: "1"
    assert_select ".index-browse__range", text: /1–1.*\/.*1/m

    get root_path(q: "wea")
    assert_select "#search-suggestions[hidden][role='listbox']" do
      assert_select "button[role='option'][data-completion='weather']", text: /weather.*plugin.*@acme/m, count: 1
    end

    normalized = create_published(publisher: @acme, name: "dash-name", category: "other",
      tags: [], summary: "Normalized identifier", downloads: 0,
      first_at: 2.months.ago, last_at: 2.months.ago)
    get root_path(q: "plugin:dashname")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, normalized.name), count: 1
    assert_select ".index-picker__card-foot", text: /plugin:name/, count: 0
  end

  test "query category operators intersect instead of overriding the active category filter" do
    get root_path(q: "category:system", category: "widgets")
    assert_response :success
    assert_select ".index-picker__row", 0
    assert_select ".index-search__result", text: "0"
    assert_select ".index-browse__range", text: /0–0.*\/.*0/m
  end

  test "unknown category and tag params are ignored, not errors" do
    get root_path(category: "nonsense", tag: "alsononsense")
    assert_response :success
    assert_select ".index-picker__row", 3
  end

  test "updated sort puts the freshest release first" do
    get root_path(sort: "updated")
    names = css_select(".index-picker__row").map { |row| row["data-name"] }
    assert_operator names.index("mixer"), :<, names.index("weather")
  end

  test "plain search keeps original direct matches ahead of the fuzzy fallback" do
    phrase_match = create_published(publisher: @acme, name: "clock-helper", category: "other",
      tags: %w[clock], summary: "A complete clock dashboard", downloads: 0,
      first_at: 2.months.ago, last_at: 2.months.ago)
    get root_path(q: "clock dashboard")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, phrase_match.name), count: 1
    assert_select ".index-picker__card-foot", text: /text:clock dashboard/, count: 0

    fuzzy_only = create_published(publisher: @acme, name: "remote-tool", category: "other",
      tags: %w[w-e-a-t-h-e-r z-e-b-r-a], summary: "Unrelated utility", downloads: 0,
      first_at: 2.months.ago, last_at: 2.months.ago)

    get root_path(q: "weather")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, @weather.name), count: 1
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, fuzzy_only.name), count: 0

    get root_path(q: "audio")
    assert_select ".index-picker__row", 1 do |rows|
      assert_match "mixer", rows.first.text
      assert_match "acme", rows.first.text
      assert_match(/verified/i, rows.first.text)
      assert_no_match(/tag:audio|system\//, rows.first.text)
    end

    get root_path(q: "wthr")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, @weather.name), count: 1
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, fuzzy_only.name), count: 0

    get root_path(q: "zbr")
    assert_select ".index-picker__row > a.index-picker__card-open[href=?]", plugin_path(@acme.name, fuzzy_only.name), count: 1
  end

  test "search treats LIKE metacharacters literally and bounds long input" do
    get root_path(q: "%")
    assert_select ".index-picker__row", 0
    get root_path(q: "_")
    assert_select ".index-picker__row", 0

    get root_path(q: "_" * 200)
    assert_response :success
    assert_select "input[name='q'][role='combobox']:not([maxlength])", 1
    assert_equal HomeController::MAX_QUERY_LENGTH, css_select("input[name='q'][role='combobox']").first["value"].each_char.count
  end

  test "empty operators and the term bound preserve directory semantics without an explain block" do
    get root_path(q: 'plugin:""')
    assert_select ".index-query-plan", 0
    assert_select ".index-picker__row", 3
    assert_select ".index-search__result", text: "3"
    assert_select ".index-browse__range", text: /1–3.*\/.*3/m

    get root_path(q: "plugin:")
    assert_select ".index-picker__row", 0
    assert_select ".index-search__result", text: "0"
    assert_select ".index-browse__range", text: /0–0.*\/.*0/m

    [ "@", '@""', "author:@", 'author:"@"' ].each do |empty_author|
      get root_path(q: empty_author)
      assert_select ".index-picker__row", 3
    end

    get root_path(q: ([ "clock" ] * 25).join(" "))
    assert_select ".index-picker__row", 1
  end

  test "search exposes every supported example and the compact result range" do
    get root_path(q: "bar-widget")

    assert_select ".index-search.is-active .index-search__examples", 1
    examples = [ "wireguard", "@publisher", "author:publisher", "plugin:weather",
                 "kind:bar-widget", "tag:media", "category:system", 'text:"power profile"' ]
    assert_select "nav.index-search__examples[aria-label='Search examples']" do
      examples.each do |example|
        assert_select "a[href=?][translate='no']", root_path(q: example), text: example, count: 1
      end
    end
    assert_select ".index-query-plan", 0
    assert_select ".index-search__result", text: "3"
    assert_select ".index-browse__range", text: /1–3.*\/.*3/m
    assert_select ".index-picker__row", 3
    assert_select ".index-picker__card", HomeController::PER_PAGE
  end

  test "Most Wanted uses exactly seven calendar days of demand" do
    DailyDownload.create!(plugin_version: @weather.versions.order(:id).last, date: 6.days.ago.to_date, count: 1)
    DailyDownload.create!(plugin_version: @mixer.versions.order(:id).last, date: 7.days.ago.to_date, count: 1_000)
    DailyDownload.create!(plugin_version: @fresh.versions.order(:id).last, date: Date.tomorrow, count: 2_000)

    get root_path

    assert_select ".recent-card--master", text: /weather/, count: 1
    assert_select ".fetch__row[data-value='1']", text: /last 7 days.*1/im, count: 1
  end

  test "Most Wanted resolves tied weekly demand through ratings views and lifetime installs" do
    contenders = [
      create_published(publisher: @acme, name: "rated", category: "other", tags: [], summary: "Rated",
        downloads: 10, first_at: 2.months.ago, last_at: 2.months.ago),
      create_published(publisher: @acme, name: "viewed", category: "other", tags: [], summary: "Viewed",
        downloads: 10, first_at: 2.months.ago, last_at: 2.months.ago),
      create_published(publisher: @acme, name: "installed", category: "other", tags: [], summary: "Installed",
        downloads: 900, first_at: 2.months.ago, last_at: 2.months.ago),
      create_published(publisher: @acme, name: "runner-up", category: "other", tags: [], summary: "Runner up",
        downloads: 800, first_at: 2.months.ago, last_at: 2.months.ago)
    ]
    contenders.each do |plugin|
      DailyDownload.create!(plugin_version: plugin.versions.order(:id).last, date: Date.current, count: 5)
    end
    contenders[1].update!(views_count: 100)
    contenders[2].update!(views_count: 50)
    contenders[3].update!(views_count: 50)
    2.times do |index|
      Rating.create!(plugin: contenders[0], user: User.create!(email_address: "rated-#{index}@example.com", name: "Rater"), value: 5)
    end
    contenders.drop(1).each_with_index do |plugin, index|
      Rating.create!(plugin:, user: User.create!(email_address: "other-#{index}@example.com", name: "Rater"), value: 4)
    end

    get root_path

    names = css_select(".recent-band .recent-card__name").map(&:text)
    assert_equal %w[rated viewed installed runner-up], names.first(4)
  end

  test "Most Wanted and Recently Added remain independent of Browse state" do
    DailyDownload.create!(plugin_version: @fresh.versions.order(:id).last, date: Date.current, count: 1_000)

    get root_path
    assert_select ".recent-band[data-index-recent][data-controller~='recent-rotate'][data-controller~='plugin-share']:not([hidden])" do
      assert_select "#most-wanted-title", text: "Most Wanted", count: 1
      assert_select ".recent-card", 3
      assert_select ".recent-card--master", text: /fresh/, count: 1
      assert_select ".recent-band__count[aria-label*='7-day installs']", text: /3.*\/ stats/m, count: 1
      assert_select "a[href=?]", root_path(sort: "trending"), count: 1
    end
    assert_select ".recent-card--master .recent-card__art--fallback[aria-hidden='true']", 1
    assert_select ".recent-card--master" do
      assert_select "a.recent-card__open[href=?]", plugin_path(@rival.name, @fresh.name), count: 1
      assert_select "a.recent-card__name[href=?][data-action*='plugin-share#copy'][data-share-label=?]:not([aria-label])",
        plugin_path(@rival.name, @fresh.name), "Copy link to #{@fresh.full_name}", text: @fresh.name, count: 1
    end
    assert_select ".recent-card--master .recent-card__signals:not([aria-label])", text: /new.*↓ 5.*0.*0/i do
      assert_select ".visually-hidden", text: "New plugin, 5 downloads, 0 upvotes, 0 views", count: 1
      assert_select "svg.index-picker__upvote-glyph path", count: 1
      assert_select "svg.index-picker__view-glyph path + circle", count: 1
    end
    assert_select ".recent-card--master .recent-card__artifact", text: /verified.*1 B.*v1\.1\.0/i
    assert_select ".recent-stream[data-controller~='recent-stream'][data-controller~='plugin-share']" do
      assert_select "#recent-title", text: "Recently Added", count: 1
      assert_select ".recent-stream__count[aria-label=?]", "1 plugin first published in the last 14 days", text: /1.*\/ 14d/m, count: 1
      assert_select ".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__card", text: /fresh.*rival/im, count: 1 do
        assert_select "mark, b", count: 0
      end
      assert_select ".recent-stream__group--duplicate[aria-hidden='true'] .recent-stream__card", count: 1 do
        assert_select "a.recent-stream__open[tabindex='-1']", count: 1
        assert_select "a.recent-stream__name[tabindex='-1']", count: 1
      end
      assert_select ".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__card" do
        assert_select "a.recent-stream__open[href=?]", plugin_path(@rival.name, @fresh.name), count: 1
        assert_select "a.recent-stream__name[href=?][data-action*='plugin-share#copy'][data-share-label=?]:not([aria-label])",
          plugin_path(@rival.name, @fresh.name), "Copy link to #{@fresh.full_name}", text: @fresh.name, count: 1
      end
      assert_select "a.recent-stream__more[href=?]", root_path(sort: "newest"), count: 1
      assert_select "button.recent-stream__toggle[aria-label='Pause Recently Added'][hidden]", count: 1
    end

    [ root_path(category: "widgets"), root_path(q: "clock"), root_path(page: 2) ].each do |path|
      get path
      assert_select ".recent-band[data-index-recent]:not([hidden])", 1
      assert_select ".recent-stream", 1
    end
  end

  test "discovery images ignore half-synced preview metadata without changing statistical rank" do
    5.times do |index|
      plugin = create_published(publisher: @acme, name: "previewed-#{index}", category: "other",
        tags: [], summary: "Previewed", downloads: 1_000 + index, first_at: (index + 2).days.ago, last_at: 1.day.ago)
      plugin.preview_card.attach(io: StringIO.new("preview-#{index}"), filename: "preview-#{index}.webp",
        content_type: "image/webp")
      plugin.update!(preview_meta: { "card" => { "width" => 720, "height" => 405 } })
    end
    half_synced = create_published(publisher: @acme, name: "half-synced", category: "other",
      tags: [], summary: "Half synced", downloads: 2_000, first_at: 1.hour.ago, last_at: 1.hour.ago)
    half_synced.preview_card.attach(io: StringIO.new("half"), filename: "half.webp", content_type: "image/webp")

    get root_path

    assert_select ".recent-band .recent-card", count: HomeController::MOST_WANTED_LIMIT
    assert_select ".recent-band .recent-card--master", text: /half-synced/, count: 1 do
      assert_select ".recent-card__art--fallback.discovery-preview-fallback", text: "[ preview unavailable ]", count: 1
    end
    assert_select ".recent-band .recent-card .recent-card__art[src]", count: 4
    assert_select ".recent-stream__group:not(.recent-stream__group--duplicate)" do
      assert_select ".recent-stream__card", count: 7
      assert_select ".recent-stream__visual img", count: 5
      assert_select ".recent-stream__fallback.discovery-preview-fallback", text: "[ preview unavailable ]", count: 2
      assert_select ".recent-stream__primary .recent-stream__name", count: 7
      assert_select ".recent-stream__secondary .recent-stream__publisher", count: 7
      assert_select "mark, b", count: 0
    end
  end

  test "header exposes the navigation path and current section" do
    get root_path

    assert_select "nav.nav__links[aria-label='Primary navigation']" do
      assert_select "a.nav__section--active[aria-current='page'][href='/']", text: "plugins", count: 1
      assert_select "button.theme-toggle[data-theme-target~='toggle'][aria-expanded='false']", text: /theme=tokyo-night/, count: 1
      assert_select "a.nav__account[href=?]", new_session_path, text: "sign-in →", count: 1
    end
    assert_select "html[data-theme='tokyo-night']", count: 1
    assert_select "meta[name='theme-color'][content='#1a1b26']", count: 1
    assert_select ".nav__brand, .nav__omacom, .nav__suffix, .nav__katakana", count: 0

    get plugin_path("acme", "weather")
    assert_select "a.nav__section--active[aria-current='location'][href='/']", text: "plugins", count: 1

    get governance_path
    assert_select "a.nav__section--active[aria-current='page'][href=?]", governance_path, text: "governance", count: 1
  end

  test "footer keeps only the branded provenance line" do
    get root_path

    assert_select "footer.statusfoot .statusfoot__omacom", 1
    assert_select "footer.statusfoot .statusfoot__katakana", text: "オマコム", count: 1
    assert_select "footer.statusfoot a.statusfoot__registry[href='https://plugins.omarchy.org']", text: "plugins.omarchy.org", count: 1
    assert_select "footer.statusfoot a.statusfoot__omarchy-link[href='https://omarchy.org']" do
      assert_select "span.statusfoot__omarchy-wordmark[style*='omarchy-wordmark-'][style*='.svg']", 1
    end
    assert_select "footer.statusfoot .statusfoot__trademark", text: /PLUGINS/, count: 1
    assert_select "footer.statusfoot", text: /pending trademark/i, count: 0
    assert_select ".statusline, .statusfoot__links", 0
    assert_select "mask[id='omk-c-nav']", 0
    assert_select "mask[id='omk-c-footer']", 1
  end

  test "detail page links category and tags back to the filtered directory" do
    get plugin_path("acme", "weather")
    assert_select ".page-head__chips a[href=?]", root_path(category: "widgets")
    assert_select ".page-head__chips a[href=?]", root_path(tag: "weather")
  end
end

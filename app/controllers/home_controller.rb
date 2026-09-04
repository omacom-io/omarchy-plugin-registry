class HomeController < ApplicationController
  include ConditionalGet
  allow_unauthenticated_access

  # Computed per row from the versions table — plugins.updated_at is useless
  # here (any counter or metadata write touches it). The published-state enum
  # integer is bound, not interpolated: a SQL constant assembled by hand is
  # the shape a scanner has to flag, and it costs nothing to bind it.
  PUBLISHED_STATE = PluginVersion.states.fetch(:published)
  LAST_PUBLISHED_SQL = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, PUBLISHED_STATE ]).freeze
    (SELECT MAX(pv.published_at) FROM plugin_versions pv
      WHERE pv.plugin_id = plugins.id AND pv.state = ?)
  SQL
  FIRST_PUBLISHED_SQL = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, PUBLISHED_STATE ]).freeze
    (SELECT MIN(pv.published_at) FROM plugin_versions pv
      WHERE pv.plugin_id = plugins.id AND pv.state = ?)
  SQL
  LATEST_SIZE_SQL = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, PUBLISHED_STATE ]).freeze
    (SELECT pv.size_bytes FROM plugin_versions pv
      WHERE pv.plugin_id = plugins.id AND pv.state = ? AND pv.version = plugins.latest_version LIMIT 1)
  SQL
  UPVOTES_SQL = <<~SQL.squish.freeze
    (SELECT COUNT(*) FROM ratings r WHERE r.plugin_id = plugins.id AND r.value >= 4)
  SQL
  WEEK_DOWNLOADS_SQL = <<~SQL.squish.freeze
    (SELECT COALESCE(SUM(dd.count), 0) FROM daily_downloads dd
      JOIN plugin_versions pv ON pv.id = dd.plugin_version_id
      WHERE pv.plugin_id = plugins.id
        AND dd.date BETWEEN date('now', '-6 days') AND date('now'))
  SQL
  ORIGINAL_TEXT_SEARCH_SQL = <<~SQL.squish.freeze
    LOWER(plugins.name) LIKE :q ESCAPE '\\' OR LOWER(COALESCE(plugins.summary, '')) LIKE :q ESCAPE '\\'
      OR LOWER(plugins.normalized_name) LIKE :q ESCAPE '\\'
  SQL
  BROAD_SEARCH_SQL = <<~SQL.squish.freeze
    LOWER(plugins.name) LIKE :q ESCAPE '\\' OR LOWER(COALESCE(plugins.summary, '')) LIKE :q ESCAPE '\\'
      OR LOWER(plugins.normalized_name) LIKE :q ESCAPE '\\' OR LOWER(COALESCE(plugins.category, 'other')) LIKE :q ESCAPE '\\'
      OR EXISTS (SELECT 1 FROM json_each(plugins.tags) WHERE LOWER(json_each.value) LIKE :q ESCAPE '\\')
      OR EXISTS (SELECT 1 FROM json_each(plugins.kinds) WHERE LOWER(json_each.value) LIKE :q ESCAPE '\\')
      OR EXISTS (SELECT 1 FROM publishers
        WHERE publishers.id = plugins.publisher_id
          AND (LOWER(publishers.name) LIKE :q ESCAPE '\\' OR LOWER(publishers.normalized_name) LIKE :q ESCAPE '\\'))
  SQL
  PLUGIN_SEARCH_SQL = <<~SQL.squish.freeze
    LOWER(plugins.name) LIKE :q ESCAPE '\\' OR LOWER(plugins.normalized_name) LIKE :q ESCAPE '\\'
      OR EXISTS (SELECT 1 FROM publishers
        WHERE publishers.id = plugins.publisher_id
          AND LOWER(publishers.name || '/' || plugins.name) LIKE :q ESCAPE '\\')
  SQL

  SORTS = {
    "downloads" => "plugins.downloads_count DESC",
    "trending" => "#{WEEK_DOWNLOADS_SQL} DESC",
    "rating" => "CASE WHEN ratings_count = 0 THEN 0 ELSE ratings_sum * 1.0 / ratings_count END DESC, ratings_count DESC",
    "updated" => "#{LAST_PUBLISHED_SQL} DESC NULLS LAST",
    "newest" => "plugins.created_at DESC",
    "name" => "plugins.name ASC"
  }.freeze

  PER_PAGE = 9
  MOST_WANTED_LIMIT = 5
  RECENT_STREAM_LIMIT = 12
  FILTER_TAGS = %w[security].freeze
  MOST_WANTED_ORDER = "week_downloads DESC, upvotes_count DESC, plugins.views_count DESC, plugins.downloads_count DESC".freeze
  JSON_PER_PAGE = 24
  MAX_QUERY_LENGTH = 160
  MAX_QUERY_TERMS = 24
  # JSON callers may ask for a larger page so building a local index doesn't
  # take dozens of round trips. Capped: an uncapped page size on a directory
  # heading for six figures is a cheap way to make the server do a lot of work.
  MAX_PER_PAGE = 100

  def index
    @query = params[:q].to_s.unicode_normalize(:nfc).strip.first(MAX_QUERY_LENGTH)
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "downloads"
    @page = [ params[:page].to_i, 1 ].max
    @category = params[:category] if Registry::Taxonomy.category?(params[:category])
    @tag = params[:tag] if Registry::Taxonomy.tag?(params[:tag])
    @per_page = page_size
    @terms = parse_query(@query)

    # Fallback-tier selection, cards, counts, and facets must describe one
    # catalog state. A read transaction keeps all of these SQLite reads on the
    # same snapshot while publication or takedown writes wait.
    ActiveRecord::Base.transaction do
      # Plugins without a published version stay visible while genuinely in
      # review; burned names and rejected-only submissions don't pollute the
      # directory.
      scope = filtered_scope
      # id as tiebreaker: downloads/rating ties would otherwise let rows drift
      # between pages as OFFSET slides across an unstable order
      plugins = scope
        .select("plugins.*", "#{FIRST_PUBLISHED_SQL} AS first_published_at", "#{LAST_PUBLISHED_SQL} AS last_published_at",
          "#{LATEST_SIZE_SQL} AS latest_size_bytes", "#{UPVOTES_SQL} AS upvotes_count",
          "COUNT(*) OVER() AS directory_total")
        .order(Arel.sql(SORTS[@sort])).order(:id)
        .offset((@page - 1) * @per_page).limit(@per_page + 1).to_a
      @more = plugins.length > @per_page
      @plugins = plugins.first(@per_page)
      # The window count and cards come from one SQLite snapshot, so a concurrent
      # publication cannot make the JSON page contradict its own total.
      @total = plugins.first&.directory_total&.to_i || scope.unscope(:select).count
      @category_counts = category_counts(Plugin.directory_visible)
      @tag_counts = tag_counts(Plugin.directory_visible)
      @result_category_counts = if @query.present?
        category_counts(scope)
      else
        {}
      end
      @search_plan = Registry::SearchQueryPlan.call(
        query: @query, terms: @terms, plain_tier: @plain_match_tier, category: @category, tag: @tag
      )
      @search_suggestions = if @query.present? && (@page == 1 || @per_page < MAX_PER_PAGE)
        Registry::SearchSuggestions.call(@query, category: @category, tag: @tag)
      else
        []
      end
      @catalog_revision = catalog_revision if request.format.json?
      # Independent discovery remains stable while Browse changes result windows.
      # Most Wanted is statistics-led rather than editorial: current demand
      # (7-day installs), then positive ratings, views, and lifetime installs.
      @wanted = if request.format.html?
        Plugin.directory_visible.includes(:publisher).with_attached_preview_card
          .select("plugins.*", "#{FIRST_PUBLISHED_SQL} AS first_published_at", "#{LAST_PUBLISHED_SQL} AS last_published_at",
            "#{LATEST_SIZE_SQL} AS latest_size_bytes", "#{UPVOTES_SQL} AS upvotes_count",
            "#{WEEK_DOWNLOADS_SQL} AS week_downloads")
          .order(Arel.sql(MOST_WANTED_ORDER)).order(:id).limit(MOST_WANTED_LIMIT).to_a
      else
        []
      end

      @show_recent = true
      @card_recency_cutoff = ApplicationHelper::CARD_RECENCY.ago
      recent_scope = Plugin.directory_visible
        .where("#{FIRST_PUBLISHED_SQL} > ?", @card_recency_cutoff)
      @recent_total = recent_scope.count
      @recent = recent_scope.includes(:publisher).with_attached_preview_card
        .select("plugins.*", "#{FIRST_PUBLISHED_SQL} AS first_published_at", "#{LAST_PUBLISHED_SQL} AS last_published_at")
        .order(Arel.sql("first_published_at DESC")).order(:id).limit(RECENT_STREAM_LIMIT).to_a
      @stats = {
        plugins: Plugin.listed.where.not(latest_version: nil).count,
        publishers: Publisher.claimed.count,
        downloads: Plugin.sum(:downloads_count),
        week: DailyDownload.where(date: 6.days.ago.to_date..Date.current).sum(:count),
        updated_at: PluginVersion.published.maximum(:published_at)
      }
      wanted_signature = @wanted.map do |plugin|
        [ plugin.id, plugin.try(:week_downloads).to_i, plugin.try(:upvotes_count).to_i,
          plugin.views_count, plugin.downloads_count ]
      end
      freshen(@plugins, @wanted, wanted_signature, @recent, @query, @sort, @category, @tag,
        @page, @per_page, @more, @total, @catalog_revision, @category_counts.sort,
        @tag_counts.sort, @result_category_counts.sort, @search_plan, @search_suggestions,
        @recent_total, @stats.values, last_modified: false)
      # Jbuilder asks installability and attachment questions. Render before
      # leaving the read transaction so those implicit reads share this snapshot.
      render unless performed?
    end
  end

  private

  # One aggregate row detects directory membership, content, ordering-stat,
  # view, and download changes without materializing the catalog in Ruby on
  # every JSON page. It is intentionally global: an unrelated catalog write
  # may conservatively invalidate a catalog snapshot, but no relevant write can be missed.
  def catalog_revision
    facts = Plugin.directory_visible.unscope(:select, :order).pick(
      Arel.sql("COUNT(*)"),
      Arel.sql("MAX(plugins.updated_at)"),
      Arel.sql("COALESCE(SUM(plugins.downloads_count), 0)"),
      Arel.sql("COALESCE(SUM(plugins.views_count), 0)"),
      Arel.sql("COALESCE(SUM(plugins.ratings_count), 0)"),
      Arel.sql("COALESCE(SUM(plugins.ratings_sum), 0)")
    )
    window = 7.days.ago.to_date..Date.current
    daily_facts = DailyDownload.where(date: window).pick(
      Arel.sql("COUNT(*)"), Arel.sql("COALESCE(SUM(daily_downloads.count), 0)")
    )
    Digest::SHA256.hexdigest([ Date.current.iso8601, *facts, *daily_facts ].map(&:to_s).join("\0"))
  end

  # The web browser is deliberately one nine-card terminal window. Native
  # clients keep the wider historical default and may opt into a larger, bounded page.
  def page_size
    return PER_PAGE unless request.format.json?
    requested = params[:per_page].to_i
    requested.positive? ? requested.clamp(1, MAX_PER_PAGE) : JSON_PER_PAGE
  end

  # Typed terms mirror the marketplace vocabulary while plain terms remain a
  # broad search. Input is normalized and bounded before this parser runs.
  def parse_query(query)
    terms = { text: [], fulltext: [], plugins: [], publishers: [], tags: [], kinds: [], categories: [] }
    query.scan(/(?:[^\s:]+:)?"[^"]*"|\S+/).first(MAX_QUERY_TERMS).each do |token|
      key, raw_value = token.match(/\A(plugin|text|tag|kind|category|author):(.+)\z/i)&.captures
      if key
        value = query_value(raw_value)
        next if value.blank?
        bucket = { "plugin" => :plugins, "text" => :fulltext, "tag" => :tags, "kind" => :kinds,
                   "category" => :categories, "author" => :publishers }.fetch(key.downcase)
        value = value.delete_prefix("@") if bucket == :publishers
        terms[bucket] << value if value.present?
      elsif token.start_with?("@")
        value = query_value(token.delete_prefix("@"))
        terms[:publishers] << value if value.present?
      else
        value = query_value(token)
        terms[:text] << value if value.present?
      end
    end
    terms[:publishers].map! { |publisher| NameRules.normalize(publisher) }
    terms.transform_values!(&:uniq)
  end

  def query_value(value)
    value = value[1...-1] if value.start_with?("\"") && value.end_with?("\"")
    value.to_s.downcase.strip
  end

  def category_values(categories)
    values = Array(categories).compact
    values += [ nil ] if values.include?("other")
    values
  end

  def category_counts(scope)
    counts = scope.unscope(:select, :order).group(:category).count
    counts["other"] = counts.fetch("other", 0) + counts.delete(nil).to_i
    counts
  end

  def tag_counts(scope)
    scope.unscope(:select, :order).joins("JOIN json_each(plugins.tags) AS browse_tags")
      .group("browse_tags.value")
      .pluck(Arel.sql("browse_tags.value"), Arel.sql("COUNT(DISTINCT plugins.id)"))
      .to_h
  end

  def filtered_scope
    @plain_match_tier = nil
    scope = Plugin.directory_visible.includes(:publisher).with_attached_preview_card

    @terms[:fulltext].each do |term|
      like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      scope = scope.where(BROAD_SEARCH_SQL, q: like)
    end
    @terms[:plugins].each do |term|
      like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
      scope = scope.where(PLUGIN_SEARCH_SQL, q: like)
    end
    if @terms[:publishers].any?
      scope = scope.joins(:publisher)
        .where(publishers: { normalized_name: @terms[:publishers].map { |p| NameRules.normalize(p) } })
    end
    scope = scope.where(category: category_values(@terms[:categories])) if @terms[:categories].any?
    @terms[:tags].each { |tag| scope = scope.where(json_membership("plugins.tags"), tag) }
    @terms[:kinds].each { |kind| scope = scope.where(json_membership("plugins.kinds"), kind) }
    # URL facets are independent constraints. Keeping them outside the parsed
    # operator buckets prevents category:system + ?category=widgets becoming an
    # accidental OR union while preserving the registry's established operators.
    scope = scope.where(category: category_values(@category)) if @category
    scope = scope.where(json_membership("plugins.tags"), @tag) if @tag

    # Keep the original registry engine as the direct pass: all plain words form
    # one case-insensitive phrase over name, summary, and normalized name. The
    # broader catalog search and then name-first subsequence matching remain
    # fallbacks, but cannot swamp a real direct match with summary noise.
    if @terms[:text].any?
      phrase = @terms[:text].join(" ")
      exact_like = "%#{ActiveRecord::Base.sanitize_sql_like(phrase)}%"
      exact_scope = scope.where(ORIGINAL_TEXT_SEARCH_SQL, q: exact_like)
      catalog_scope = @terms[:text].reduce(scope) do |result, term|
        like = "%#{ActiveRecord::Base.sanitize_sql_like(term)}%"
        result.where(BROAD_SEARCH_SQL, q: like)
      end
      plugin_fuzzy_scope = @terms[:text].reduce(scope) do |result, term|
        result.where(PLUGIN_SEARCH_SQL, q: fuzzy_like(term))
      end
      scope = if exact_scope.exists?
        @plain_match_tier = :direct
        exact_scope
      elsif catalog_scope.exists?
        @plain_match_tier = :catalog
        catalog_scope
      elsif plugin_fuzzy_scope.exists?
        @plain_match_tier = :plugin_fuzzy
        plugin_fuzzy_scope
      else
        @plain_match_tier = :catalog_fuzzy
        @terms[:text].reduce(scope) { |result, term| result.where(BROAD_SEARCH_SQL, q: fuzzy_like(term)) }
      end
    end
    scope
  end

  def fuzzy_like(term)
    escaped = term.each_char.map { |character| ActiveRecord::Base.sanitize_sql_like(character) }
    "%#{escaped.join('%')}%"
  end

  # Membership test inside a JSON-array column (SQLite json_each, same as the
  # trending window above — this app is SQLite in every environment).
  def json_membership(column)
    "EXISTS (SELECT 1 FROM json_each(#{column}) WHERE json_each.value = ?)"
  end
end

# The directory a native browser lists from. Same query parameters as the web
# page (q, sort, category, tag, page) — including marketplace-compatible typed
# operators — so the two surfaces can never disagree
# about what a search returns.
json.schema_version 1
json.catalog_revision @catalog_revision

json.query do
  json.q @query
  json.sort @sort
  json.category @category
  json.tag @tag
end

json.page do
  json.number @page
  json.per_page @per_page
  json.total @total
  json.more @more
end

# Canonical server explanation and bounded Fish-style completions. Neither
# changes result semantics: the directory query above remains authoritative.
json.plan @search_plan
json.suggestions @search_suggestions

json.stats @stats

# The curated browse vocabulary. Published here so a client can render facet
# chips without hardcoding a copy that drifts when governance adds a category.
json.taxonomy do
  json.sorts HomeController::SORTS.keys
  json.search_operators %w[plugin: kind: tag: text: category: author: @]
  json.categories Registry::Taxonomy::CATEGORIES do |slug|
    json.slug slug
    json.label Registry::Taxonomy.label(slug)
    json.count @category_counts.fetch(slug, 0)
    json.match_count @result_category_counts.fetch(slug, 0)
  end
  json.tags Registry::Taxonomy::TAGS
  json.tag_counts HomeController::FILTER_TAGS.index_with { |tag| @tag_counts.fetch(tag, 0) }
  json.max_tags Registry::Taxonomy::MAX_TAGS
end

json.plugins @plugins do |plugin|
  json.partial! "plugins/plugin", plugin: plugin
  match_type, match_value = plugin_match_reason(plugin)
  json.match do
    json.type match_type
    json.value match_value
  end
  json.card do
    json.new plugin_new?(plugin)
    json.upvotes plugin.try(:upvotes_count).to_i
    json.views plugin.views_count
    json.verified plugin.try(:latest_size_bytes).present?
    json.size_bytes plugin.try(:latest_size_bytes)&.to_i
  end
end

# Independent first-page discovery: remains available while Browse is filtered.
json.recent(@show_recent ? @recent : []) do |plugin|
  json.partial! "plugins/plugin", plugin: plugin
end

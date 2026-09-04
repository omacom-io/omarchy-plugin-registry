module ApplicationHelper
  def render_markdown(text, asset_base: nil)
    return "" if text.blank?
    html = Commonmarker.to_html(text,
      options: { extension: { table: true, strikethrough: true, autolink: true, tasklist: true },
                 render: { unsafe: false } })
    html = rewrite_relative_images(html, asset_base) if asset_base.present?
    html.html_safe
  end

  # A README is written to be read INSIDE its repository, so its screenshots
  # are repo-relative ("preview.png"). Served from a plugin page those resolve
  # against /plugins/<publisher>/ and 404 — every imported README with an
  # inline screenshot rendered as a broken image. Rewrite them onto the exact
  # commit the version was built from: raw.githubusercontent.com content is
  # immutable per sha, so the picture cannot change under a reviewed version.
  #
  # Relative LINKS (./CONTRIBUTING.md) are still broken — a raw URL would
  # serve unrendered markdown, so they need the repo's tree URL instead.
  def rewrite_relative_images(html, base)
    doc = Nokogiri::HTML5.fragment(html)
    doc.css("img[src]").each do |img|
      src = img["src"].to_s.strip
      next if src.blank? || src.start_with?("#") || src.match?(%r{\A(?:[a-z][a-z0-9+.\-]*:|//)}i)
      img["src"] = URI.join(base, src.delete_prefix("./")).to_s
    rescue URI::Error
      next
    end
    doc.to_html
  end

  # The pinned raw-content base for a version's own source, or nil when we
  # have no provenance to pin to (nothing is rewritten then — a wrong guess
  # would point a plugin page at somebody else's repository).
  def readme_asset_base(version)
    repository = version&.provenance&.dig("repository")
    sha = version&.provenance&.dig("sha")
    return nil if repository.blank? || sha.blank?
    "https://raw.githubusercontent.com/#{repository}/#{sha}/"
  end

  def compact_number(number)
    number_to_human(number, format: "%n%u", precision: 3, significant: true,
      units: { thousand: "k", million: "M", billion: "B" }, strip_insignificant_zeros: true)
  end

  def compact_byte_size(number)
    bytes = number.to_i
    return "#{bytes} B" if bytes < 1024

    number_to_human_size(bytes, precision: 3, significant: true, strip_insignificant_zeros: true)
  end

  COMPACT_UTC_MONTHS = %w[jan feb mar apr may jun jul aug sep oct nov dec].freeze

  def compact_utc_timestamp(time)
    utc = time.utc
    format("%02d %s %02d · %02d:%02d UTC",
      utc.day, COMPACT_UTC_MONTHS.fetch(utc.month - 1), utc.year % 100, utc.hour, utc.min)
  end

  # Turns a manifest-provided repository URL into { icon:, label:, url: } for the
  # sidebar Source row, or nil when the value isn't a linkable http(s) URL.
  def source_repo(url)
    uri = URI.parse(url.to_s)
    return nil unless uri.is_a?(URI::HTTP) && uri.host.present?
    host = uri.host.downcase.delete_prefix("www.")
    icon, label =
      case host
      when "github.com" then [ :github, "GitHub" ]
      when "gitlab.com" then [ :gitlab, "GitLab" ]
      when /\Agitlab\./ then [ :gitlab, host ]
      when "codeberg.org" then [ :link, "Codeberg" ]
      when "bitbucket.org" then [ :link, "Bitbucket" ]
      else [ :link, host ]
      end
    { icon: icon, label: label, url: uri.to_s }
  rescue URI::InvalidURIError
    nil
  end

  # Share cards and JSON payloads both need absolute URLs — a native client
  # reading /plugins/acme/weather.json can't resolve a root-relative path.
  def absolute_url(path)
    return nil if path.blank?
    "#{DataPlane.base_url}#{path}"
  end

  DEFAULT_META_DESCRIPTION = "The Omarchy plugin registry — hosted, scanned, revocable. Browse, install, and publish plugins for Omarchy.".freeze
  DEFAULT_THEME = "tokyo-night".freeze
  THEMES = %w[
    catppuccin catppuccin-latte ethereal everforest flexoki-light gruvbox hackerman
    kanagawa last-horizon lumon lupine matte-black miasma nord osaka-jade retro-82 ristretto
    rose-pine solitude tokyo-night vantablack white
  ].freeze

  # OpenGraph/Twitter tags with absolute URLs. Pages call this through
  # content_for(:social); the layout falls back to the site-wide card.
  def social_meta(title:, description:, image_path:, url_path:)
    safe_join([
      tag.meta(property: "og:type", content: "website"),
      tag.meta(property: "og:site_name", content: "Omarchy Plugins"),
      tag.meta(property: "og:title", content: title),
      tag.meta(property: "og:description", content: description),
      tag.meta(property: "og:url", content: absolute_url(url_path)),
      tag.meta(property: "og:image", content: absolute_url(image_path)),
      tag.meta(property: "og:image:width", content: 1200),
      tag.meta(property: "og:image:height", content: 630),
      tag.meta(name: "twitter:card", content: "summary_large_image"),
      tag.meta(name: "twitter:title", content: title),
      tag.meta(name: "twitter:description", content: description)
    ], "\n")
  end

  # Directory links that keep the current search/sort/filter state — pass only
  # what changes. Page deliberately resets unless overridden: a filter change
  # always lands on its own first page.
  def directory_path(overrides = {})
    root_path({ q: @query.presence, sort: (@sort if @sort != "downloads"),
                category: @category, tag: @tag }.merge(overrides).compact)
  end

  def spark_series(plugin_id)
    return nil unless @daily_installs
    ((PluginCardData::SPARK_DAYS - 1).days.ago.to_date..Date.current).map do |day|
      @daily_installs[[ plugin_id, day ]] || 0
    end
  end

  def sparkline_svg(values, width: 132, height: 30)
    max = values.max.to_i
    step = values.size > 1 ? (width - 4).to_f / (values.size - 1) : 0
    points = values.each_with_index.map do |value, index|
      x = (2 + index * step).round(1)
      y = max.zero? ? height - 3 : (height - 3 - (value.to_f / max) * (height - 8)).round(1)
      "#{x},#{y}"
    end.join(" ")
    tag.svg(viewBox: "0 0 #{width} #{height}", class: "spark", preserveAspectRatio: "none", aria: { hidden: true }) do
      tag.polyline(points: points, fill: "none", stroke: "currentColor", "stroke-width": 1.5)
    end
  end

  def plugin_match_reason(plugin, terms = @terms)
    return [ "sorted", @sort ] if @query.blank?

    name = plugin.name.downcase
    normalized_name = plugin.normalized_name.downcase
    publisher = plugin.publisher.normalized_name
    publisher_name = plugin.publisher.name.downcase
    category = plugin.category.presence || "other"
    return [ "plugin", "name" ] if terms[:plugins].any? do |term|
      name.include?(term) || normalized_name.include?(term) || "#{publisher_name}/#{name}".include?(term)
    end
    if (kind = plugin.kinds.find { |value| terms[:kinds].include?(value.to_s.downcase) })
      return [ "kind", kind ]
    end
    return [ "author", "@#{plugin.publisher.name}" ] if terms[:publishers].include?(publisher)
    if (tag_value = plugin.tags.find { |value| terms[:tags].include?(value.to_s.downcase) })
      return [ "tag", tag_value ]
    end
    return [ "category", category ] if terms[:categories].include?(category.downcase)
    return [ "text", terms[:fulltext].first ] if terms[:fulltext].any?

    if @plain_match_tier == :direct && terms[:text].any?
      phrase = terms[:text].join(" ")
      return [ "plugin", "name" ] if name.include?(phrase) || normalized_name.include?(phrase)
      return [ "text", phrase ] if plugin.summary.to_s.downcase.include?(phrase)
    end

    terms[:text].each do |term|
      return [ "plugin", "name" ] if name.include?(term)
      if (kind = plugin.kinds.find { |value| value.to_s.downcase.include?(term) })
        return [ "kind", kind ]
      end
      if (tag_value = plugin.tags.find { |value| value.to_s.downcase.include?(term) })
        return [ "tag", tag_value ]
      end
      return [ "category", category ] if category.downcase.include?(term)
      return [ "author", "@#{plugin.publisher.name}" ] if publisher.include?(term)
    end

    terms[:text].each do |term|
      return [ "plugin", "name" ] if subsequence_match?(name, term)
      if (kind = plugin.kinds.find { |value| subsequence_match?(value.to_s.downcase, term) })
        return [ "kind", kind ]
      end
      if (tag_value = plugin.tags.find { |value| subsequence_match?(value.to_s.downcase, term) })
        return [ "tag", tag_value ]
      end
      return [ "category", category ] if subsequence_match?(category.downcase, term)
      return [ "author", "@#{plugin.publisher.name}" ] if subsequence_match?(publisher, term)
    end

    [ "text", terms[:text].first || @query ]
  end

  def subsequence_match?(value, query)
    index = 0
    query.each_char.all? do |character|
      found = value.index(character, index)
      index = found.to_i + 1
      found.present?
    end
  end

  CARD_RECENCY = 14.days

  def card_recency_cutoff
    @card_recency_cutoff ||= CARD_RECENCY.ago
  end

  def plugin_new?(plugin)
    first = plugin.try(:first_published_at)
    first.present? && Time.zone.parse(first.to_s) > card_recency_cutoff
  end

  # "New" for a first release, "Updated" for a fresh version of an existing
  # plugin — driven by the first/last_published_at columns the directory query
  # selects alongside the row.
  def card_activity_badge(plugin)
    if plugin_new?(plugin)
      tag.span "New", class: "badge badge--ok"
    elsif (last = plugin.try(:last_published_at)).present? && Time.zone.parse(last.to_s) > card_recency_cutoff
      tag.span "Updated", class: "badge"
    end
  end

  def plugin_card_label(plugin)
    if plugin.category.present?
      Registry::Taxonomy.label(plugin.category)
    elsif plugin.kinds.any?
      plugin.kinds.first.to_s.humanize
    else
      "Plugin"
    end
  end

  def state_badge(state)
    tone = case state.to_s
    when "published", "active" then "badge--ok"
    when "yanked", "rejected", "security_holding" then "badge--danger"
    when "quarantined", "held" then "badge--warning"
    else ""
    end
    tag.span state.to_s.humanize, class: "badge #{tone}"
  end
end

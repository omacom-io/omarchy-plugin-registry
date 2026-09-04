module Registry
  class SearchSuggestions
    LIMIT = 6
    CANDIDATE_LIMIT = 24
    MAX_QUERY_LENGTH = 160
    TYPES = %w[plugin kind author tag category].freeze
    TYPE_ORDER = TYPES.index_by(&:itself).freeze

    def self.call(query, category: nil, tag: nil)
      new(query, category:, tag:).call
    end

    def initialize(query, category:, tag:)
      @query = query.to_s.unicode_normalize(:nfc).strip.first(MAX_QUERY_LENGTH)
      @category = category
      @tag = tag
      @candidates = []
    end

    def call
      parse_draft
      # The local registry keeps one visible q expression rather than the
      # marketplace's separate committed-term state. Do not offer a completion
      # that merely copies earlier constraints without applying them.
      return [] if @before.present? || @needle.blank? || @mode == :text

      case @mode
      when :plugin then add_plugins
      when :author then add_authors
      when :kind then add_kinds
      when :tag then add_tags
      when :category then add_categories
      else
        add_plugins
        add_kinds
        add_authors
        add_tags
        add_categories
      end

      @candidates
        .uniq { |candidate| [ candidate[:type], candidate[:completion].downcase ] }
        .sort_by { |candidate| [ *candidate.delete(:rank), TYPE_ORDER.fetch(candidate[:type]), candidate[:label].downcase ] }
        .first(LIMIT)
    end

    private

    def parse_draft
      match = @query.match(/(?:\A|[\u0009-\u000d\u0020])([^\u0009-\u000d\u0020]*)\z/)
      @token = match&.captures&.first.to_s
      @before = match ? @query[0...match.begin(1)] : ""
      @mode = :plain
      raw_value = @token

      if (typed = @token.match(/\A(plugin|kind|tag|category|text|author):(.*)\z/i))
        @mode = typed[1].downcase.to_sym
        raw_value = typed[2]
      elsif @token.start_with?("@")
        @mode = :author_shorthand
        raw_value = @token.delete_prefix("@")
      end

      @mode = :author if @mode == :author_shorthand
      @author_shorthand = @token.start_with?("@")
      @needle = raw_value.delete_prefix("@").downcase
      @needle = "" if @needle.include?("\"")
    end

    def add_plugins
      prefix = "#{ActiveRecord::Base.sanitize_sql_like(@needle)}%"
      prefix_order = ActiveRecord::Base.sanitize_sql_array([ <<~SQL.squish, prefix, prefix ])
        CASE WHEN LOWER(plugins.name) LIKE ? ESCAPE '\\' THEN 0
          WHEN LOWER(publishers.name || '/' || plugins.name) LIKE ? ESCAPE '\\' THEN 1 ELSE 2 END
      SQL
      plugin_scope.where(
        "LOWER(plugins.name) LIKE :q ESCAPE '\\' OR " \
          "LOWER(publishers.name || '/' || plugins.name) LIKE :q ESCAPE '\\'",
        q: fuzzy_pattern
      ).order(Arel.sql(prefix_order)).order(downloads_count: :desc, id: :asc).limit(CANDIDATE_LIMIT)
        .pluck("plugins.name", "publishers.name").each do |name, publisher|
          replacement = if @mode == :plugin
            token_value = @needle.include?("/") ? "#{publisher}/#{name}" : name
            "plugin:#{token_value}"
          else
            name
          end
          add_candidate("plugin", name, replacement, "@#{publisher}", [ name, "#{publisher}/#{name}" ])
        end
    end

    def add_authors
      plugin_scope.where("LOWER(publishers.name) LIKE :q ESCAPE '\\'", q: fuzzy_pattern)
        .group("publishers.id", "publishers.name")
        .order(Arel.sql(prefix_order("publishers.name")))
        .order(Arel.sql("COUNT(DISTINCT plugins.id) DESC"), "publishers.name")
        .limit(CANDIDATE_LIMIT)
        .pluck("publishers.name", Arel.sql("COUNT(DISTINCT plugins.id)")).each do |publisher, count|
          replacement = (@author_shorthand || @mode == :plain) ? "@#{publisher}" : "author:#{publisher}"
          add_candidate("author", "@#{publisher}", replacement, plugin_count(count), [ publisher ])
        end
    end

    def add_kinds
      kind_candidates.each do |kind, count|
        add_candidate("kind", kind, "kind:#{kind}", plugin_count(count), [ kind ])
      end
    end

    def add_tags
      tag_candidates.each do |tag, count|
        add_candidate("tag", tag, "tag:#{tag}", plugin_count(count), [ tag ])
      end
    end

    def add_categories
      category = "COALESCE(plugins.category, 'other')"
      plugin_scope.where("LOWER(#{category}) LIKE :q ESCAPE '\\'", q: fuzzy_pattern)
        .group(Arel.sql(category)).order(Arel.sql(prefix_order(category)))
        .order(Arel.sql("COUNT(DISTINCT plugins.id) DESC"), Arel.sql(category))
        .limit(CANDIDATE_LIMIT).count.each do |name, count|
          add_candidate("category", name, "category:#{name}", plugin_count(count), [ name ])
        end
    end

    def kind_candidates
      plugin_scope.joins("JOIN json_each(plugins.kinds) AS suggestion_kinds")
        .where("LOWER(suggestion_kinds.value) LIKE :q ESCAPE '\\'", q: fuzzy_pattern)
        .group("suggestion_kinds.value")
        .order(Arel.sql(prefix_order("suggestion_kinds.value")))
        .order(Arel.sql("COUNT(DISTINCT plugins.id) DESC"), Arel.sql("suggestion_kinds.value"))
        .limit(CANDIDATE_LIMIT)
        .pluck(Arel.sql("suggestion_kinds.value"), Arel.sql("COUNT(DISTINCT plugins.id)"))
    end

    def tag_candidates
      plugin_scope.joins("JOIN json_each(plugins.tags) AS suggestion_tags")
        .where("LOWER(suggestion_tags.value) LIKE :q ESCAPE '\\'", q: fuzzy_pattern)
        .group("suggestion_tags.value")
        .order(Arel.sql(prefix_order("suggestion_tags.value")))
        .order(Arel.sql("COUNT(DISTINCT plugins.id) DESC"), Arel.sql("suggestion_tags.value"))
        .limit(CANDIDATE_LIMIT)
        .pluck(Arel.sql("suggestion_tags.value"), Arel.sql("COUNT(DISTINCT plugins.id)"))
    end

    def plugin_scope
      scope = Plugin.directory_visible.joins(:publisher)
      scope = scope.where(category: category_values(@category)) if @category
      if @tag
        scope = scope.where(
          "EXISTS (SELECT 1 FROM json_each(plugins.tags) WHERE json_each.value = ?)", @tag
        )
      end
      scope
    end

    def category_values(category)
      category == "other" ? [ "other", nil ] : category
    end

    def add_candidate(type, label, replacement, detail, values)
      label = label.to_s
      detail = detail.to_s
      completion = "#{@before}#{replacement}"
      strings = [ label, detail, completion ]
      return if strings.any? { |value| value.each_char.count > MAX_QUERY_LENGTH || value.match?(/[\u0000-\u001f\u007f-\u009f]/) }
      rank = values.filter_map { |value| fuzzy_rank(value) }.min
      return unless rank

      @candidates << { type:, label:, completion:, detail:, rank: }
    end

    def fuzzy_rank(value)
      haystack = value.to_s.downcase
      contiguous = haystack.index(@needle)
      return [ 0, contiguous, haystack.length ] if contiguous

      previous = -1
      gaps = 0
      @needle.each_char do |character|
        position = haystack.index(character, previous + 1)
        return nil unless position
        gaps += position - previous - 1 if previous >= 0
        previous = position
      end
      [ 1, gaps, haystack.length ]
    end

    def fuzzy_pattern
      escaped = @needle.each_char.map { |character| ActiveRecord::Base.sanitize_sql_like(character) }
      "%#{escaped.join('%')}%"
    end

    def prefix_order(column)
      prefix = "#{ActiveRecord::Base.sanitize_sql_like(@needle)}%"
      ActiveRecord::Base.sanitize_sql_array([ "CASE WHEN LOWER(#{column}) LIKE ? ESCAPE '\\' THEN 0 ELSE 1 END", prefix ])
    end

    def plugin_count(count)
      "#{count} #{count.to_i == 1 ? 'plugin' : 'plugins'}"
    end
  end
end

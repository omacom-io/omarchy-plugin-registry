module Registry
  class SearchQueryPlan
    TYPED_TERMS = {
      plugins: [ "plugin", "plugin name + source", "substring" ],
      fulltext: [ "text", "all catalog fields", "substring" ],
      publishers: [ "author", "publisher identity", "exact publisher" ],
      tags: [ "tag", "taxonomy tags", "exact tag" ],
      kinds: [ "kind", "manifest kinds", "exact kind" ],
      categories: [ "category", "taxonomy category", "exact category" ]
    }.freeze

    PLAIN_TIERS = {
      direct: [ "name + normalized + summary", "joined phrase substring" ],
      catalog: [ "all catalog fields", "every term substring" ],
      plugin_fuzzy: [ "plugin name + source", "every term name subsequence" ],
      catalog_fuzzy: [ "all catalog fields", "every term subsequence" ]
    }.freeze

    def self.call(query:, terms:, plain_tier:, category: nil, tag: nil)
      new(query:, terms:, plain_tier:, category:, tag:).call
    end

    def initialize(query:, terms:, plain_tier:, category:, tag:)
      @query = query.to_s
      @terms = terms
      @plain_tier = plain_tier
      @category = category
      @tag = tag
    end

    def call
      return { parse: "none", scope: "directory", match: "sorted" } if @query.blank?

      ignored = ignored_operator_count
      parsed = parse_parts
      if parsed.empty? && ignored.positive?
        return { parse: "empty operator", scope: "none", match: "ignored" }
      end
      parsed << "#{ignored} ignored" if ignored.positive?
      parse = parsed.join(" + ")
      represented_terms = @terms.values.sum(&:size) + ignored
      parse = "#{query_tokens.size} tokens → #{parse}" if query_tokens.size > represented_terms

      scopes = []
      matches = []
      if @terms[:text].any?
        scope, match = PLAIN_TIERS.fetch(@plain_tier || :catalog_fuzzy)
        scopes << scope
        matches << match
      end

      TYPED_TERMS.each do |bucket, (_label, scope, match)|
        next if @terms[bucket].empty?
        scopes << scope
        matches << quantified_match(bucket, match)
      end

      if @category
        scopes << "taxonomy category"
        matches << (@terms[:categories].any? ? "exact category (query AND filter)" : "exact category filter")
      end
      if @tag
        scopes << "taxonomy tags"
        matches << (@terms[:tags].any? ? "exact tags (query AND filter)" : "exact tag filter")
      end

      {
        parse:,
        scope: scopes.uniq.join(" + ").presence || "none",
        match: matches.uniq.join(" + ").presence || "ignored"
      }
    end

    private

    def parse_parts
      parts = []
      plain_count = @terms[:text].size
      parts << (plain_count == 1 ? "plain term" : "#{plain_count} plain terms") if plain_count.positive?

      TYPED_TERMS.each do |bucket, (label, _scope, _match)|
        count = @terms[bucket].size
        next if count.zero?
        parts << (count == 1 ? "operator:#{label}" : "#{count} #{label} filters")
      end
      parts
    end

    def quantified_match(bucket, match)
      count = @terms[bucket].size
      return match if count == 1
      join = %i[publishers categories].include?(bucket) ? "OR" : "AND"
      "#{match} (#{join})"
    end

    def ignored_operator_count
      query_tokens.count do |token|
        typed = token.match(/\A(plugin|text|tag|kind|category|author):(.+)\z/i)
        if typed
          value = query_value(typed[2])
          value = value.delete_prefix("@") if typed[1].casecmp?("author")
          value.blank?
        elsif token.start_with?("@")
          query_value(token.delete_prefix("@")).blank?
        else
          false
        end
      end
    end

    def query_tokens
      @query.scan(/(?:[^\s:]+:)?"[^"]*"|\S+/).first(HomeController::MAX_QUERY_TERMS)
    end

    def query_value(value)
      value = value[1...-1] if value.start_with?("\"") && value.end_with?("\"")
      value.to_s.downcase.strip
    end
  end
end

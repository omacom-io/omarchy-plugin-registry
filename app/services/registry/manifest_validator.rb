module Registry
  # Server-side mirror of omarchy-plugin-validate plus registry-only rules.
  # All registry metadata derives from the manifest inside the tarball — no
  # sidecar metadata is accepted (kills the manifest-confusion bug class).
  #
  # KIND_ENTRY_RULES is the registry's authoritative kind/entry-point contract;
  # the Quattro-side validator must stay in lockstep (tracked in docs/client-spec.md).
  class ManifestValidator
    # kind => required entryPoints key + allowed extensions. This mirrors the
    # Quattro-side omarchy-plugin-validate kind table EXACTLY (bar-widget maps
    # to the camelCase barWidget key; the rest match their kind name).
    KIND_ENTRY_RULES = {
      "bar" => { key: "bar", extensions: %w[.qml] },
      "bar-widget" => { key: "barWidget", extensions: %w[.qml] },
      "menu" => { key: "menu", extensions: %w[.qml] },
      "overlay" => { key: "overlay", extensions: %w[.qml] },
      "panel" => { key: "panel", extensions: %w[.qml] },
      "service" => { key: "service", extensions: %w[.qml .sh] }
    }.freeze
    ALLOWED_KINDS = KIND_ENTRY_RULES.keys.freeze
    # Deferred by the design ("maybe: themes join the same registry") — no
    # client contract or conformance fixture exists yet, so accepting the kind
    # would promise installs Quattro can't perform.
    DEFERRED_KINDS = %w[theme].freeze
    ID_FORMAT = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/
    MAX_DESCRIPTION_LENGTH = 512

    # The complete SPDX license list, vendored from spdx.org (config/spdx.json,
    # list version recorded inside) — real identifiers only, all of them.
    SPDX_DATA = JSON.parse(Rails.root.join("config/spdx.json").read).freeze
    SPDX_LICENSE_IDS = SPDX_DATA["licenses"].to_set.freeze
    SPDX_EXCEPTION_IDS = SPDX_DATA["exceptions"].to_set.freeze

    attr_reader :errors

    def initialize(manifest:, publisher:, plugin_name:, tarball:)
      @manifest = manifest
      @publisher = publisher
      @plugin_name = plugin_name
      @tarball = tarball
      @errors = []
    end

    def valid?
      check_schema_version
      check_required_fields
      check_id
      check_version
      check_kinds
      check_entry_points
      check_license
      check_repository
      check_min_omarchy_version
      check_category
      check_tags
      errors.empty?
    end

    private

    attr_reader :manifest, :publisher, :plugin_name, :tarball

    def check_schema_version
      errors << "schemaVersion must be 1" unless manifest["schemaVersion"] == 1
    end

    def check_required_fields
      %w[id name version kinds entryPoints].each do |field|
        errors << "manifest missing required field: #{field}" if manifest[field].blank?
      end
      # Types are part of the contract — a numeric or object-valued field must
      # never reach a version row for clients to choke on
      %w[id name version license minOmarchyVersion repository author description].each do |field|
        value = manifest[field]
        # nil-check, not present? — `false` and other non-strings must fail
        errors << "manifest #{field} must be a string" if !value.nil? && !value.is_a?(String)
      end
      name = manifest["name"]
      if name.is_a?(String) && (name.length > 80 || name.match?(/[[:cntrl:]]/))
        errors << "manifest name must be at most 80 printable characters"
      end
      description = manifest["description"]
      if description.is_a?(String) &&
          (description.length > MAX_DESCRIPTION_LENGTH || description.match?(/[[:cntrl:]]/))
        errors << "manifest description must be at most #{MAX_DESCRIPTION_LENGTH} printable characters"
      end
    end

    def check_id
      id = manifest["id"].to_s
      return if id.blank?
      errors << "manifest id has illegal characters" unless id.match?(ID_FORMAT)
      expected = "#{publisher.name}.#{plugin_name}"
      errors << "manifest id must be #{expected} (got #{id})" unless id == expected
    end

    def check_version
      version = manifest["version"].to_s
      return if version.blank?
      errors << "version must be strict semver (got #{version})" unless Semver.valid?(version)
      # Build metadata is ignored in semver precedence — 1.0.0+a and 1.0.0+b
      # would be "equal" versions with different bytes, which immutability
      # cannot allow
      errors << "version must not carry build metadata (+...)" if version.include?("+")
    end

    # Part of the signed compatibility contract — clients resolve against it,
    # so malformed values must never reach the index.
    def check_min_omarchy_version
      min = manifest["minOmarchyVersion"]
      return if min.nil?
      unless min.is_a?(String) && Semver.valid?(min)
        errors << "minOmarchyVersion must be a strict semver string (got #{min.inspect})"
      end
    end

    def check_kinds
      kinds = manifest["kinds"]
      unless kinds.is_a?(Array) && kinds.any? && kinds.all? { |k| k.is_a?(String) }
        return errors << "kinds must be a non-empty array of strings"
      end
      deferred = kinds & DEFERRED_KINDS
      errors << "kinds not yet supported: #{deferred.join(', ')} (themes are deferred until the client contract lands)" if deferred.any?
      unknown = kinds - ALLOWED_KINDS - DEFERRED_KINDS
      errors << "unknown kinds: #{unknown.join(', ')}" if unknown.any?
    end

    def check_entry_points
      entry_points = manifest["entryPoints"]
      return errors << "entryPoints must be an object" unless entry_points.is_a?(Hash)

      # Quattro semantics: every declared kind must have its mapped entry-point
      # key; extra keys are allowed but every value is validated.
      kinds = Array(manifest["kinds"])
      kinds.select { |k| k.is_a?(String) }.each do |kind|
        rule = KIND_ENTRY_RULES[kind]
        next unless rule
        unless entry_points.key?(rule[:key])
          errors << "kind '#{kind}' requires an 'entryPoints.#{rule[:key]}' to load"
        end
      end

      extension_rules = KIND_ENTRY_RULES.values.to_h { |r| [ r[:key], r[:extensions] ] }
      entry_points.each do |key, path|
        unless path.is_a?(String) && !path.start_with?("/") && !path.split("/").include?("..")
          errors << "entry point for #{key} must be a relative path inside the plugin"
          next
        end
        errors << "entry point #{path} not found in tarball" unless tarball.include?(path)

        allowed = extension_rules[key]
        if allowed && allowed.exclude?(File.extname(path).downcase)
          errors << "entry point for #{key} must be #{allowed.join(' or ')} (got #{path})"
        end
      end
    end

    # A license is optional — many imported legacy plugins never declared one,
    # and the directory shows "No license" honestly instead of gating on it.
    # A DECLARED license must still be a real SPDX expression.
    def check_license
      license = manifest["license"].to_s
      return if license.blank?
      errors << "license must be a known SPDX expression (got #{license})" unless valid_spdx_expression?(license)
    end

    # "MIT", "(MIT OR Apache-2.0)", "GPL-3.0-only WITH GCC-exception-3.1", …
    # Recursive-descent over the SPDX expression grammar:
    #   expr := term ((OR|AND) term)* ; term := ID [WITH EXC] | "(" expr ")"
    def valid_spdx_expression?(expression)
      parser = SpdxExpressionParser.new(expression)
      parser.valid?
    end

    class SpdxExpressionParser
      # Real SPDX expressions are tiny; these bounds turn pathological input
      # (64KB of nested parens) into a normal validation failure instead of a
      # SystemStackError in the worker
      MAX_TOKENS = 64
      MAX_DEPTH = 8

      def initialize(expression)
        @tokens = expression.to_s.gsub("(", " ( ").gsub(")", " ) ").split(/\s+/).reject(&:empty?)
        @position = 0
        @depth = 0
      end

      def valid?
        return false if @tokens.empty? || @tokens.length > MAX_TOKENS
        parse_expr && @position == @tokens.length
      end

      private

      def peek = @tokens[@position]
      def advance = @tokens[@position].tap { @position += 1 }

      def parse_expr
        return false unless parse_term
        while %w[OR AND].include?(peek)
          advance
          return false unless parse_term
        end
        true
      end

      def parse_term
        if peek == "("
          @depth += 1
          return false if @depth > MAX_DEPTH
          advance
          ok = parse_expr && peek == ")"
          @depth -= 1
          return false unless ok
          advance
          true
        elsif SPDX_LICENSE_IDS.include?(peek)
          advance
          if peek == "WITH"
            advance
            return false unless SPDX_EXCEPTION_IDS.include?(peek)
            advance
          end
          true
        else
          false
        end
      end
    end

    # Optional curated browse metadata — one category, up to three tags, all
    # from the fixed Taxonomy lists (free-form labels fragment the directory).
    def check_category
      category = manifest["category"]
      return if category.nil?
      unless category.is_a?(String) && Taxonomy.category?(category)
        errors << "category must be one of: #{Taxonomy::CATEGORIES.join(', ')} (got #{category.inspect})"
      end
    end

    def check_tags
      tags = manifest["tags"]
      return if tags.nil?
      unless tags.is_a?(Array) && tags.all? { |t| t.is_a?(String) }
        return errors << "tags must be an array of strings"
      end
      errors << "at most #{Taxonomy::MAX_TAGS} tags allowed" if tags.length > Taxonomy::MAX_TAGS
      errors << "tags must be unique" if tags.uniq.length != tags.length
      unknown = tags.reject { |t| Taxonomy.tag?(t) }
      errors << "unknown tags: #{unknown.join(', ')} (allowed: #{Taxonomy::TAGS.join(', ')})" if unknown.any?
    end

    # Rendered as a link on the plugin page — https only, sane length.
    def check_repository
      repository = manifest["repository"]
      return if repository.blank?
      uri = URI.parse(repository.to_s) rescue nil
      unless uri.is_a?(URI::HTTPS) && repository.to_s.length <= 300
        errors << "repository must be an https:// URL"
        return
      end
      # Accidental credentials would persist in the immutable tarball AND
      # render publicly — refuse at the door
      errors << "repository URL must not contain credentials" if uri.userinfo.present?
    end
  end
end

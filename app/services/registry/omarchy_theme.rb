require "digest"

module Registry
  # Reads the local Omarchy theme state for the same-machine development UI.
  # Only a fixed, bounded set of color values is projected; theme files are
  # never executed and arbitrary TOML content is never returned to the browser.
  class OmarchyTheme
    MAX_NAME_BYTES = 96
    MAX_COLORS_BYTES = 32.kilobytes
    NAME = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/
    HEX = /\A#[0-9a-fA-F]{6}\z/
    OUTPUT_KEYS = ([ "background", "foreground", "cursor" ] + (0..15).map { |index| "color#{index}" }).freeze
    ANSI_NAMES = %w[
      background red green yellow blue magenta cyan foreground muted bright_red bright_green
      bright_yellow bright_blue bright_magenta bright_cyan bright_foreground
    ].freeze
    IGNORED_THEME_KEYS = %w[
      accent action active_border_color active_tab_background base00 base01 base02 base03 base04 base05
      base06 base07 base08 base09 base0A base0B base0C base0D base0E base0F base10 base11 base12 base13
      base14 base15 base16 base17 bg bright_fg bright_purple brown dark_background dark_bg darker_background
      darker_bg dark_fg dark_foreground error error_text fg hyprland_active_border hyprland_inactive_border
      info light_fg light_foreground lighter_background lighter_bg link mode muted_text orange purple
      selection selection_background selection_foreground success theme_type warning
    ].freeze
    INPUT_KEYS = (OUTPUT_KEYS + ANSI_NAMES).uniq.freeze
    KNOWN_KEYS = (INPUT_KEYS + IGNORED_THEME_KEYS).uniq.freeze
    ASSIGNMENT = /\A\s*([A-Za-z][A-Za-z0-9_]*)\s*=\s*"([^"\\\r\n]*)"\s*(?:#.*)?(?:\r?\n)?\z/
    FORBIDDEN_CONTROLS = /[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/

    def self.state_directory
      configured = ENV["OMARCHY_THEME_STATE_DIR"].presence
      return Pathname.new(configured).expand_path if configured
      return unless Rails.env.development?

      Pathname.new(ENV.fetch("XDG_STATE_HOME", File.join(Dir.home, ".local/state")))
        .join("omarchy/current")
    end

    def self.stock_themes_directory
      Pathname.new(ENV.fetch("OMARCHY_THEME_STOCK_DIR", "/usr/share/omarchy/themes")).expand_path
    end

    def self.theme_lock_path
      configured = ENV["OMARCHY_THEME_LOCK_PATH"].presence
      return Pathname.new(configured).expand_path if configured

      Pathname.new(ENV.fetch("XDG_RUNTIME_DIR", "/tmp")).join("omarchy-theme-set.lock")
    end

    def self.available?
      directory = state_directory
      directory && directory.join("theme.name").file? && directory.join("theme/colors.toml").file?
    end

    def self.current(supported_themes:)
      directory = state_directory
      return unless directory

      with_theme_lock do
        name_before = read_name(directory.join("theme.name"))
        colors_bytes = read_bounded(directory.join("theme/colors.toml"), MAX_COLORS_BYTES)
        name_after = read_name(directory.join("theme.name"))
        next unless name_before && name_before == name_after && colors_bytes

        colors = parse_colors(colors_bytes)
        next unless colors

        {
          name: name_before,
          theme: stock_theme(name_before, colors, supported_themes),
          revision: Digest::SHA256.hexdigest("#{name_before}\0#{colors_bytes}"),
          colors: colors
        }
      end
    end

    def self.with_theme_lock
      path = theme_lock_path
      return unless path.file?

      File.open(path, read_only_flags) do |file|
        return unless file.stat.file? && file.flock(File::LOCK_SH | File::LOCK_NB)

        yield
      ensure
        file&.flock(File::LOCK_UN)
      end
    rescue SystemCallError, IOError
      nil
    end
    private_class_method :with_theme_lock

    def self.stock_theme(name, colors, supported_themes)
      return unless supported_themes.include?(name)

      stock_bytes = read_bounded(stock_themes_directory.join(name, "colors.toml"), MAX_COLORS_BYTES)
      name if stock_bytes && parse_colors(stock_bytes) == colors
    end
    private_class_method :stock_theme

    def self.read_name(path)
      bytes = read_bounded(path, MAX_NAME_BYTES)
      return unless bytes

      text = valid_text(bytes)
      return unless text

      match = text.match(/\A(#{NAME.source.delete_prefix("\\A").delete_suffix("\\z")})(?:\n)?\z/)
      match[1] if match
    end
    private_class_method :read_name

    def self.read_bounded(path, limit)
      File.open(path, read_only_flags) do |file|
        return unless file.stat.file?

        bytes = file.read(limit + 1)
        bytes if bytes && bytes.bytesize <= limit
      end
    rescue SystemCallError, IOError
      nil
    end
    private_class_method :read_bounded

    def self.read_only_flags
      flags = File::RDONLY | File::NONBLOCK
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      flags
    end
    private_class_method :read_only_flags

    def self.valid_text(bytes)
      text = bytes.dup.force_encoding(Encoding::UTF_8)
      return unless text.valid_encoding?
      return if text.match?(FORBIDDEN_CONTROLS)
      return if text.gsub("\r\n", "").include?("\r")

      text
    end
    private_class_method :valid_text

    def self.parse_colors(bytes)
      text = valid_text(bytes)
      return unless text

      colors = {}
      seen = {}

      text.each_line do |line|
        next if line.match?(/\A\s*(?:#.*)?(?:\r?\n)?\z/)

        match = line.match(ASSIGNMENT)
        return unless match

        key, value = match.captures
        return unless KNOWN_KEYS.include?(key) && !seen.key?(key)

        seen[key] = true
        if INPUT_KEYS.include?(key)
          return unless HEX.match?(value)

          colors[key] = value.downcase
        elsif key == "mode"
          return unless %w[dark light].include?(value)
        end
      end

      legacy = normalize_legacy(colors)
      modern = normalize_modern(colors)
      return if legacy && modern && legacy != modern

      legacy || modern
    end
    private_class_method :parse_colors

    def self.normalize_legacy(colors)
      return unless OUTPUT_KEYS.all? { |key| colors.key?(key) }

      colors.slice(*OUTPUT_KEYS)
    end
    private_class_method :normalize_legacy

    def self.normalize_modern(colors)
      return unless ANSI_NAMES.all? { |key| colors.key?(key) }

      normalized = {
        "background" => colors.fetch("background"),
        "foreground" => colors.fetch("foreground"),
        "cursor" => colors["cursor"] || colors.fetch("bright_foreground")
      }
      ANSI_NAMES.each_with_index { |key, index| normalized["color#{index}"] = colors.fetch(key) }
      normalized
    end
    private_class_method :normalize_modern
  end
end

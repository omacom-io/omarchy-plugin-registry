require "test_helper"
require "tmpdir"
require "timeout"

class OmarchyThemeSyncTest < ActionDispatch::IntegrationTest
  COLORS = {
    "background" => "#1a1b26",
    "foreground" => "#c0caf5",
    "cursor" => "#ffffff",
    **(0..15).to_h { |index| [ "color#{index}", format("#%06x", 0x202020 + index * 0x030303) ] }
  }.freeze

  test "local endpoint returns only a bounded normalized palette" do
    with_theme_state("velvet_night.v2") do
      get omarchy_theme_path

      assert_response :success
      assert_equal "no-store", response.headers["Cache-Control"]
      assert_nil response.headers["Access-Control-Allow-Origin"]
      payload = response.parsed_body
      assert_equal "velvet_night.v2", payload.fetch("name")
      assert_nil payload.fetch("theme")
      assert_match(/\A[0-9a-f]{64}\z/, payload.fetch("revision"))
      assert_equal COLORS.transform_values(&:downcase), payload.fetch("colors")
      assert_equal %w[colors name revision theme], payload.keys.sort

      get root_path
      assert_response :success
      assert_select "[data-controller~='theme'][data-theme-omarchy-url-value=?]", omarchy_theme_path, count: 1
    end
  end

  test "stock Omarchy colors.toml names normalize to exact ANSI slots" do
    with_theme_state("catppuccin") do |directory|
      File.binwrite(directory.join("theme/colors.toml"),
        file_fixture("omarchy_themes/catppuccin/colors.toml").binread)

      get omarchy_theme_path

      assert_response :success
      payload = response.parsed_body
      assert_equal "catppuccin", payload.fetch("theme")
      colors = payload.fetch("colors")
      assert_equal "#1e1e2e", colors.fetch("color0")
      assert_equal "#f38ba8", colors.fetch("color1")
      assert_equal "#a6e3a1", colors.fetch("color2")
      assert_equal "#89b4fa", colors.fetch("color4")
      assert_equal "#585b70", colors.fetch("color8")
      assert_equal "#cdd6f4", colors.fetch("color15")
      assert_equal colors.fetch("color15"), colors.fetch("cursor")
    end
  end

  test "a customized stock theme name uses its live colors instead of the stock preset" do
    with_theme_state("catppuccin") do |directory|
      customized = file_fixture("omarchy_themes/catppuccin/colors.toml").binread
        .sub('red = "#f38ba8"', 'red = "#010203"')
      File.binwrite(directory.join("theme/colors.toml"), customized)

      get omarchy_theme_path

      assert_response :success
      assert_nil response.parsed_body.fetch("theme")
      assert_equal "#010203", response.parsed_body.dig("colors", "color1")
    end
  end

  test "custom themes expose colors without pretending to be a picker preset" do
    with_theme_state("velvetnight") do |directory|
      File.open(directory.join("theme/colors.toml"), "a") do |file|
        file.puts('selection_foreground = "#102030"', 'selection_background = "#f0f2f4"')
      end
      get omarchy_theme_path

      assert_response :success
      assert_nil response.parsed_body.fetch("theme")
      assert_equal "velvetnight", response.parsed_body.fetch("name")
    end
  end

  test "missing lock and binary or control-laden state files fail closed" do
    with_theme_state("velvetnight") do |directory|
      lock_path = Pathname.new(ENV.fetch("OMARCHY_THEME_LOCK_PATH"))
      lock_path.delete
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      File.write(lock_path, "")

      name_path = directory.join("theme.name")
      File.binwrite(name_path, "velvetnight\0\n")
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      File.binwrite(name_path, "velvetnight\xFF\n".b)
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      File.write(name_path, "velvetnight\n")

      colors_path = directory.join("theme/colors.toml")
      valid_colors = File.binread(colors_path)
      colors_path.delete
      File.mkfifo(colors_path)
      assert_nil Timeout.timeout(1) {
        Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      }
      colors_path.delete
      File.binwrite(colors_path, valid_colors)

      [ "# invalid \xFF\n".b, "# invalid \0\n".b, "# bare carriage return\r".b,
        "# forbidden control \x01\n".b ].each do |suffix|
        File.binwrite(colors_path, valid_colors + suffix)
        assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      end
    end
  end

  test "remote requests cannot read the host theme" do
    with_theme_state("catppuccin") do
      get omarchy_theme_path, headers: { "REMOTE_ADDR" => "203.0.113.10" }

      assert_response :not_found
      assert_empty response.body
    end
  end

  test "malformed duplicate incomplete and oversized states fail closed" do
    with_theme_state("catppuccin") do |directory|
      colors_path = directory.join("theme/colors.toml")

      File.open(colors_path, "a") { |file| file.puts('color1 = "#ffffff"') }
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      write_colors(colors_path, COLORS.except("color15"))
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      write_colors(colors_path, COLORS.merge("color4" => "red"))
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      File.write(colors_path, "[palette]\n")
      write_colors(colors_path, COLORS, mode: "a")
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      File.write(colors_path, "notes = \"\"\"\n#{COLORS.map { |key, value| %(#{key} = \"#{value}\") }.join("\n")}\n\"\"\"\n")
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      File.binwrite(colors_path, "#" * (Registry::OmarchyTheme::MAX_COLORS_BYTES + 1))
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      File.write(directory.join("theme.name"), "../catppuccin\n")
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
    end
  end

  test "theme reads fail closed while Omarchy holds its exclusive theme-set lock" do
    with_theme_state("catppuccin") do |directory|
      lock = File.open(ENV.fetch("OMARCHY_THEME_LOCK_PATH"), "w")
      lock.flock(File::LOCK_EX)
      File.write(directory.join("theme.name"), "velvetnight\n")
      assert_nil Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)

      write_colors(directory.join("theme/colors.toml"), COLORS)
      lock.flock(File::LOCK_UN)
      payload = Registry::OmarchyTheme.current(supported_themes: ApplicationHelper::THEMES)
      assert_equal "velvetnight", payload.fetch(:name)
      assert_nil payload.fetch(:theme)
    ensure
      lock&.flock(File::LOCK_UN)
      lock&.close
    end
  end

  private

  def with_theme_state(name)
    Dir.mktmpdir("registry-omarchy-theme") do |path|
      directory = Pathname.new(path)
      directory.join("theme").mkpath
      File.write(directory.join("theme.name"), "#{name}\n")
      write_colors(directory.join("theme/colors.toml"), COLORS)
      previous_state = ENV["OMARCHY_THEME_STATE_DIR"]
      previous_stock = ENV["OMARCHY_THEME_STOCK_DIR"]
      previous_lock = ENV["OMARCHY_THEME_LOCK_PATH"]
      ENV["OMARCHY_THEME_STATE_DIR"] = directory.to_s
      ENV["OMARCHY_THEME_STOCK_DIR"] = file_fixture("omarchy_themes").to_s
      ENV["OMARCHY_THEME_LOCK_PATH"] = directory.join("theme-set.lock").to_s
      File.write(ENV.fetch("OMARCHY_THEME_LOCK_PATH"), "")
      yield directory
    ensure
      ENV["OMARCHY_THEME_STATE_DIR"] = previous_state
      ENV["OMARCHY_THEME_STOCK_DIR"] = previous_stock
      ENV["OMARCHY_THEME_LOCK_PATH"] = previous_lock
    end
  end

  def write_colors(path, colors, mode: "w")
    File.open(path, mode) { |file| file.write(colors.map { |key, value| %(#{key} = "#{value}") }.join("\n") + "\n") }
  end
end

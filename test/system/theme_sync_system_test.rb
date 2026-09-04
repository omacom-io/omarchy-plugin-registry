require "application_system_test_case"
require "digest"

class ThemeSyncSystemTest < ApplicationSystemTestCase
  COLORS = {
    "background" => "#102030",
    "foreground" => "#f0f2f4",
    "cursor" => "#ffffff",
    "color0" => "#102030",
    "color1" => "#e06070",
    "color2" => "#70c080",
    "color3" => "#d0b060",
    "color4" => "#809ee0",
    "color5" => "#b080d0",
    "color6" => "#60b0c0",
    "color7" => "#d0d5dc",
    "color8" => "#687080",
    "color9" => "#f07080",
    "color10" => "#80d090",
    "color11" => "#e0c070",
    "color12" => "#90aef0",
    "color13" => "#c090e0",
    "color14" => "#70c0d0",
    "color15" => "#ffffff"
  }.freeze

  test "every stock preset uses the exact Omarchy ANSI slots" do
    visit root_path

    stock_palettes = JSON.parse(file_fixture("omarchy_stock_palettes.json").read)
    expected_themes = ApplicationHelper::THEMES
    assert_equal 22, stock_palettes.size
    assert_equal expected_themes.sort, stock_palettes.keys.sort

    stock_palettes.each do |theme, colors|
      expected = (0..15).to_h { |index| [ format("slot%02d", index), colors.fetch("color#{index}") ] }
      expected["cursor"] = colors.fetch("cursor")
      actual = page.evaluate_script(<<~JS, theme)
        ((theme) => {
          document.documentElement.dataset.theme = theme
          const style = getComputedStyle(document.documentElement)
          return Object.fromEntries([
            ...Array.from({ length: 16 }, (_, index) => {
              const key = `slot${String(index).padStart(2, "0")}`
              return [key, style.getPropertyValue(`--ansi-${String(index).padStart(2, "0")}`).trim().toLowerCase()]
            }),
            ["cursor", style.getPropertyValue("--terminal-cursor").trim().toLowerCase()]
          ])
        })(arguments[0])
      JS
      assert_equal expected, actual, theme
    end
  end

  test "mobile theme selection is a compact names-only one-tap list" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 420, deviceScaleFactor: 1, mobile: false)
    visit root_path

    within ".theme-toggle" do
      assert_text "tokyo-night"
      assert_no_text "theme="
    end
    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    assert_selector ".theme-picker__name", count: ApplicationHelper::THEMES.size + 1
    assert_no_selector ".theme-picker__pane img", visible: true
    assert page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector(".theme-picker").getBoundingClientRect()
        const selected = document.querySelector(".theme-picker__item--selected").getBoundingClientRect()
        const footer = document.querySelector(".theme-picker__label").getBoundingClientRect()
        return document.activeElement.matches(".theme-picker__item--selected") &&
          selected.top >= picker.top && selected.bottom <= footer.top + 1
      })()
    JS
    assert page.evaluate_script(
      "[...document.querySelectorAll('.theme-picker__pane img')].every((image) => !image.hasAttribute('src'))"
    )

    controls = page.evaluate_script <<~JS
      (() => ({
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        buttons: [...document.querySelectorAll(".theme-picker__item")].map((button) => {
          const box = button.getBoundingClientRect()
          return { width: box.width, height: box.height }
        })
      }))()
    JS
    assert_equal 0, controls["overflow"]
    assert controls["buttons"].all? { |button| button["width"] > 0 && button["height"] >= 44 }

    find(".theme-picker__item[data-theme-value='white']", visible: true).click
    assert_no_selector ".theme-picker", visible: true
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")
    within ".theme-toggle" do
      assert_text "white"
      assert_no_text "theme="
    end
  ensure
    if page.current_url.start_with?(root_url)
      page.execute_script <<~JS
        localStorage.removeItem("registry-theme")
        localStorage.removeItem("registry-theme-mode")
      JS
    end
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "an open desktop theme picker keeps keyboard focus visible when it becomes compact" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 900, height: 420, deviceScaleFactor: 1, mobile: false)
    visit root_path
    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 420, deviceScaleFactor: 1, mobile: false)
    page.execute_script("window.dispatchEvent(new Event('resize'))")
    assert page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector(".theme-picker").getBoundingClientRect()
        const selected = document.querySelector(".theme-picker__item--selected").getBoundingClientRect()
        const footer = document.querySelector(".theme-picker__label").getBoundingClientRect()
        return document.activeElement.matches(".theme-picker__item--selected") &&
          selected.top >= picker.top && selected.bottom <= footer.top + 1
      })()
    JS
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "System follows Omarchy across pages while a manual theme remains selected" do
    visit root_path
    sync_omarchy_theme(theme_payload("catppuccin", theme: "catppuccin"), mode: "system")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/catppuccin}
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "#102030", page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--ansi-00').trim()")
    assert_equal "#ffffff", page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--terminal-cursor').trim()")
    assert_selector ".theme-picker__item[data-theme-value='system'][aria-pressed='true']", visible: :all

    custom = theme_payload("velvet_night.v2")
    sync_omarchy_theme(custom)
    assert_selector ".theme-toggle", text: %r{theme=\s*system/velvet_night\.v2}
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "#102030", page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()")

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    page.driver.browser.action.send_keys(:arrow_right).send_keys(:enter).perform
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")
    assert_equal "catppuccin", page.evaluate_script("localStorage.getItem('registry-theme')")

    changed_system = theme_payload("tokyo-night", theme: "tokyo-night",
      colors: COLORS.merge("background" => "#1a1b26"))
    sync_omarchy_theme(changed_system)
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: /theme=\s*catppuccin/

    page.driver.browser.navigate.to(governance_url)
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: /theme=\s*catppuccin/
    page.driver.browser.navigate.to(root_url)

    find(".theme-toggle").click
    2.times { find(".theme-picker__item[data-theme-value='system']", visible: true).click }
    assert_equal "system", page.evaluate_script("localStorage.getItem('registry-theme-mode')")
    assert_equal "tokyo-night", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/tokyo-night}

    page.driver.browser.navigate.to(governance_url)
    assert_equal "#102030", page.evaluate_script(
      "getComputedStyle(document.documentElement).getPropertyValue('--ansi-00').trim()")
    page.driver.browser.navigate.to(root_url)
    sync_omarchy_theme(custom)
    page.driver.browser.navigate.to(governance_url)
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "#102030", page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('--bg').trim()")
    assert_equal "rgb(128, 158, 224)", page.evaluate_script(
      "getComputedStyle(document.querySelector('.terminal-window__titlebar strong')).color")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/velvet_night\.v2}

    page.driver.browser.navigate.to(publishing_url)
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "rgb(128, 158, 224)", page.evaluate_script(
      "getComputedStyle(document.querySelector('.terminal-window__titlebar strong')).color")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/velvet_night\.v2}
  ensure
    if page.current_url.start_with?(root_url)
      page.execute_script <<~JS
        localStorage.removeItem("registry-theme")
        localStorage.removeItem("registry-theme-mode")
        localStorage.removeItem("registry-system-theme")
        localStorage.removeItem("registry-theme-override-revision")
      JS
    end
  end

  test "a legacy saved theme migrates to manual mode" do
    visit root_path
    page.execute_script <<~JS
      localStorage.removeItem("registry-theme-mode")
      localStorage.removeItem("registry-theme-override-revision")
      localStorage.setItem("registry-theme", "white")
    JS
    visit root_path

    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: /theme=\s*white/
  end

  test "a System preview stays selected when a fresh host palette arrives" do
    visit root_path
    sync_omarchy_theme(theme_payload("catppuccin", theme: "catppuccin"), mode: "system")
    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    page.driver.browser.action.send_keys(:arrow_right).send_keys(:enter).perform
    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")

    find(".theme-toggle").click
    find(".theme-picker__item[data-theme-value='system']", visible: true).click
    sync_omarchy_theme(theme_payload("velvetnight"))

    assert_selector ".theme-picker", visible: true
    assert_selector ".theme-picker__item--selected[data-theme-value='system']", visible: true
    assert_selector ".theme-picker__label", text: %r{system/velvetnight}
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")

    page.driver.browser.action.send_keys(:escape).perform
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
  end

  test "a manual preview stays open when System receives a fresh host palette" do
    visit root_path
    sync_omarchy_theme(theme_payload("catppuccin", theme: "catppuccin"), mode: "system")
    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    page.driver.browser.action.send_keys(:arrow_right).perform
    assert_selector ".theme-picker__item--selected[data-theme-value='catppuccin']", visible: true

    sync_omarchy_theme(theme_payload("velvetnight"))
    assert_selector ".theme-picker", visible: true
    assert_selector ".theme-picker__item--selected[data-theme-value='catppuccin']", visible: true
    assert_equal "catppuccin", page.evaluate_script("document.documentElement.dataset.theme")
    assert_equal "system", page.evaluate_script("localStorage.getItem('registry-theme-mode')")

    page.driver.browser.action.send_keys(:escape).perform
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/velvetnight}
  end

  test "an unavailable System option is named disabled and skipped by keyboard navigation" do
    visit root_path
    system = find(".theme-picker__item[data-theme-value='system']", visible: :all)
    assert_equal "System — follow active Omarchy theme", system["aria-label"]
    assert system.disabled?

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    assert page.evaluate_script("document.activeElement.matches('.theme-picker__item--selected')")
    3.times do
      page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }))")
    end
    assert_selector ".theme-picker__item--selected[data-theme-value='catppuccin']", visible: true
    assert_equal "catppuccin", page.evaluate_script("document.activeElement.dataset.themeValue")
    assert_equal 0, page.evaluate_script("document.querySelectorAll('.theme-picker__item:not([tabindex=\"-1\"]):not(.theme-picker__item--selected)').length")
  end

  test "reopening after a distant preview restores focus before keyboard navigation" do
    visit root_path
    sync_omarchy_theme(theme_payload("velvetnight"), mode: "system")

    find(".theme-toggle").click
    page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowLeft', bubbles: true, cancelable: true }))")
    page.driver.browser.action.send_keys(:escape).perform
    assert_no_selector ".theme-picker", visible: true

    find(".theme-toggle").click
    assert_equal "system", page.evaluate_script("document.activeElement.dataset.themeValue")
    page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }))")
    assert_selector ".theme-picker__item--selected[data-theme-value='catppuccin']", visible: true
    assert_equal "catppuccin", page.evaluate_script("document.activeElement.dataset.themeValue")
  end

  test "theme previews keep committed semantics and do not intercept controls outside the picker" do
    visit root_path
    page.execute_script <<~JS
      localStorage.setItem("registry-theme-mode", "manual")
      localStorage.setItem("registry-theme", "tokyo-night")
    JS
    visit root_path

    assert_selector ".theme-toggle", text: /theme=\s*tokyo-night/
    find(".theme-toggle").click
    page.execute_script("document.activeElement.dispatchEvent(new KeyboardEvent('keydown', { key: 'ArrowRight', bubbles: true, cancelable: true }))")
    assert_selector ".theme-picker__label", text: /previewing/i
    assert_selector ".theme-toggle", text: /theme=\s*tokyo-night/
    assert_selector ".theme-picker__item[data-theme-value='tokyo-night'][aria-pressed='true']", visible: :all
    assert_selector ".theme-picker__item--selected[aria-pressed='false']", visible: true

    governance = find("a[href='#{governance_path}']", match: :first)
    governance.send_keys(:enter)
    assert_current_path governance_path
    assert_equal "manual", page.evaluate_script("localStorage.getItem('registry-theme-mode')")
    assert_equal "tokyo-night", page.evaluate_script("localStorage.getItem('registry-theme')")
    assert_equal "tokyo-night", page.evaluate_script("document.documentElement.dataset.theme")
  end

  test "a stalled theme response times out without blocking the next poll" do
    visit root_path
    timed_out = page.driver.browser.execute_async_script <<~JS
      const done = arguments[arguments.length - 1]
      const element = document.querySelector("[data-controller~='theme']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "theme")
      controller.omarchyEndpoint = `${window.location.origin}/omarchy-theme.json`
      controller.omarchyTimeout = 30
      window.fetch = (_url, options) => new Promise((_resolve, reject) => {
        options.signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")), { once: true })
      })
      controller.pollOmarchyTheme().then(() => done(controller.omarchyRequest === null))
    JS
    assert timed_out

    sync_omarchy_theme(theme_payload("velvetnight"), mode: "system")
    assert_selector ".theme-toggle", text: %r{theme=\s*system/velvetnight}
    assert_equal "omarchy-live", page.evaluate_script("document.documentElement.dataset.theme")
  end

  test "relative-color shadow fallback remains present for older browsers" do
    visit root_path

    fallback = page.evaluate_script <<~JS
      (() => {
        const findRule = rules => {
          for (const rule of rules) {
            if (rule.conditionText === "not (color: oklch(from red calc(l * 0.45) c h))") return rule.cssText
            if (rule.cssRules) {
              const found = findRule(rule.cssRules)
              if (found) return found
            }
          }
          return null
        }
        for (const sheet of document.styleSheets) {
          const found = findRule(sheet.cssRules)
          if (found) return found
        }
        return null
      })()
    JS

    assert_includes fallback, "--shadow-ink: color-mix(in srgb, var(--bg) 33%, #000)"
  end

  test "retired themes are absent from the picker and stale storage falls back to Tokyo Night" do
    visit root_path
    page.execute_script <<~JS
      localStorage.setItem("registry-theme-mode", "manual")
      localStorage.setItem("registry-theme", "tokyo")
      localStorage.removeItem("registry-system-theme")
    JS
    visit root_path

    assert_equal "tokyo-night", page.evaluate_script("document.documentElement.dataset.theme")
    assert_nil page.evaluate_script("localStorage.getItem('registry-theme')")
    assert_no_selector ".theme-picker__item[data-theme-value='blueprint']", visible: :all
    assert_no_selector ".theme-picker__item[data-theme-value='ember']", visible: :all
    assert_no_selector ".theme-picker__item[data-theme-value='tokyo']", visible: :all
  end

  def teardown
    if page.current_url.start_with?(root_url)
      page.execute_script <<~JS
        localStorage.removeItem("registry-theme")
        localStorage.removeItem("registry-theme-mode")
        localStorage.removeItem("registry-system-theme")
        localStorage.removeItem("registry-theme-override-revision")
      JS
    end
  ensure
    super
  end

  private

  def sync_omarchy_theme(payload, mode: nil)
    page.driver.browser.execute_async_script(<<~JS, payload, mode)
      const payload = arguments[0]
      const mode = arguments[1]
      const done = arguments[arguments.length - 1]
      const element = document.querySelector("[data-controller~='theme']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "theme")
      window.__omarchyThemePayload = payload
      window.fetch = async () => new Response(JSON.stringify(window.__omarchyThemePayload), {
        status: 200, headers: { "content-type": "application/json" }
      })
      controller.omarchyEndpoint = `${window.location.origin}/omarchy-theme.json`
      if (mode) {
        controller.mode = mode
        localStorage.setItem("registry-theme-mode", mode)
      }
      controller.pollOmarchyTheme().then(done)
    JS
  end

  def theme_payload(name, theme: nil, colors: COLORS)
    {
      name: name,
      theme: theme,
      revision: Digest::SHA256.hexdigest([ name, *colors.values ].join("\0")),
      colors: colors
    }
  end
end

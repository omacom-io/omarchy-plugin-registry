require "application_system_test_case"

class MobileNavigationSystemTest < ApplicationSystemTestCase
  setup do
    publisher = Publisher.create!(name: "mobile-nav", kind: :org)
    @plugin = Plugin.create!(publisher:, name: "navigator", summary: "Mobile navigation fixture",
      latest_version: "1.0.0", category: "utilities", kinds: [ "utility" ], tags: [ "navigation" ])
    @plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "a" * 64,
      size_bytes: 1024, state: :published, published_at: Time.current)
  end

  test "mobile navigation appears only at the reference breakpoint" do
    resize_to(width: 761)
    visit root_path
    assert_selector ".mobile-nav", visible: :hidden

    resize_to(width: 760)
    assert_selector ".mobile-nav", visible: true
    assert_equal "grid", page.evaluate_script(
      'getComputedStyle(document.querySelector(".mobile-nav")).display'
    )

    visit governance_path
    assert_equal "block", page.evaluate_script(
      'getComputedStyle(document.querySelector(".terminal-window__layout")).display'
    )
    assert_equal "wrap", page.evaluate_script(
      'getComputedStyle(document.querySelector(".terminal-window__index")).flexWrap'
    )

    resize_to(width: 761)
    assert_selector ".mobile-nav", visible: :hidden
    assert_equal "grid", page.evaluate_script(
      'getComputedStyle(document.querySelector(".terminal-window__layout")).display'
    )
  end

  test "Home and Browse anchors track the visible homepage section" do
    resize_to(width: 390)
    visit root_path(sort: "name")

    assert_selector ".mobile-nav__link.is-active", text: "Home", count: 1
    within ".mobile-nav" do
      assert_link "Home", href: root_path(sort: "name", anchor: "main-content")
      assert_link "Browse", href: root_path(sort: "name", anchor: "browse")
      assert_link "Governance", href: governance_path
      assert_link "Publish", href: publishing_path
      click_link "Browse"
    end
    assert_equal "#browse", page.evaluate_script("window.location.hash")
    assert_selector ".mobile-nav__link.is-active[aria-current='location']", text: "Browse", count: 1
    assert_operator page.evaluate_script(
      'Math.abs(document.querySelector("#browse").getBoundingClientRect().top)'
    ), :<, 2

    within(".mobile-nav") { click_link "Home" }
    assert_equal "#main-content", page.evaluate_script("window.location.hash")
    assert_selector ".mobile-nav__link.is-active[aria-current='location']", text: "Home", count: 1

    find("input[name='q']").set("navigator")
    assert_current_path root_path(q: "navigator", sort: "name")
    within(".mobile-nav") { click_link "Browse" }
    assert_current_path root_path(q: "navigator", sort: "name")
    assert_equal "#browse", page.evaluate_script("window.location.hash")
    within(".mobile-nav") { click_link "Home" }
    assert_current_path root_path(q: "navigator", sort: "name")
    assert_equal "#main-content", page.evaluate_script("window.location.hash")
  end

  test "mobile navigation remains usable and unobscured across primary public views" do
    routes = [
      [ root_path, "Home" ],
      [ plugin_path("mobile-nav", @plugin.name), "Browse" ],
      [ publisher_path("mobile-nav"), "Browse" ],
      [ governance_path, "Governance" ],
      [ publishing_path, "Publish" ],
      [ new_session_path, nil ]
    ]

    [ 320, 390 ].each do |width|
      resize_to(width:)
      routes.each do |path, active_label|
        visit path
        assert_selector ".mobile-nav", visible: true
        if active_label
          assert_selector ".mobile-nav__link.is-active", text: active_label, count: 1
        else
          assert_no_selector ".mobile-nav__link.is-active"
        end
        metrics = page.evaluate_script <<~JS
          (() => {
            const nav = document.querySelector(".mobile-nav")
            const navBox = nav.getBoundingClientRect()
            const footerBox = document.querySelector(".statusfoot").getBoundingClientRect()
            window.scrollTo(0, document.documentElement.scrollHeight)
            const scrolledFooterBox = document.querySelector(".statusfoot").getBoundingClientRect()
            return {
              fixed: getComputedStyle(nav).position,
              shadow: getComputedStyle(nav).boxShadow,
              bottom: Math.abs(navBox.bottom - window.innerHeight),
              targets: [...nav.querySelectorAll("a")].map((link) => {
                const box = link.getBoundingClientRect()
                return { width: box.width, height: box.height }
              }),
              initialFooterPresent: footerBox.height > 0,
              footerClear: scrolledFooterBox.bottom <= nav.getBoundingClientRect().top + 1,
              overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
            }
          })()
        JS
        assert_equal "fixed", metrics["fixed"], "#{path} at #{width}px"
        refute_equal "none", metrics["shadow"], "#{path} at #{width}px"
        assert_operator metrics["bottom"], :<, 1, "#{path} at #{width}px"
        assert metrics["targets"].all? { |target| target["width"] >= 44 && target["height"] >= 44 },
          "undersized mobile target on #{path} at #{width}px"
        assert metrics["initialFooterPresent"], "missing footer on #{path} at #{width}px"
        assert metrics["footerClear"], "mobile navigation covers the footer on #{path} at #{width}px"
        assert_equal 0, metrics["overflow"], "horizontal overflow on #{path} at #{width}px"
      end
    end
  end

  test "top-level mobile navigation preserves active state through Turbo page changes" do
    resize_to(width: 390)
    visit root_path

    shadows = %w[tokyo-night white gruvbox].map do |theme|
      page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
      page.evaluate_script("getComputedStyle(document.querySelector('.mobile-nav')).boxShadow")
    end
    assert shadows.none? { |shadow| shadow == "none" }
    assert_equal 3, shadows.uniq.size
    page.execute_script("document.documentElement.dataset.theme = 'tokyo-night'")

    within(".mobile-nav") { click_link "Governance" }
    assert_current_path governance_path
    assert_selector ".mobile-nav__link.is-active[aria-current='page']", text: "Governance", count: 1

    within(".mobile-nav") { click_link "Publish" }
    assert_current_path publishing_path
    assert_selector ".mobile-nav__link.is-active[aria-current='page']", text: "Publish", count: 1

    within(".mobile-nav") { click_link "Browse" }
    assert_current_path root_path
    assert_equal "#browse", page.evaluate_script("window.location.hash")
    assert_selector ".mobile-nav__link.is-active[aria-current='location']", text: "Browse", count: 1
  end

  private

  def resize_to(width:)
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width:, height: 900, deviceScaleFactor: 1, mobile: false)
  end

  teardown do
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end

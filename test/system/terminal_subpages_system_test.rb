require "application_system_test_case"

class TerminalSubpagesSystemTest < ApplicationSystemTestCase
  test "governance and publishing share Tokyo Night ANSI roles and numbered alignment" do
    visit publishing_path

    publishing = page.evaluate_script <<~JS
      (() => {
        const number = document.querySelector(".terminal-step__number")
        const title = document.querySelector(".terminal-step .terminal-section__title")
        return {
          background: getComputedStyle(document.querySelector(".terminal-window--ansi")).backgroundColor,
          shadow: getComputedStyle(document.querySelector(".terminal-window")).boxShadow,
          windowTitle: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).color,
          titlebarRoute: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).color,
          windowTitleFont: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).font,
          titlebarRouteFont: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).font,
          windowTitleSpacing: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).letterSpacing,
          titlebarRouteSpacing: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).letterSpacing,
          titlebarBackground: getComputedStyle(document.querySelector(".terminal-window__titlebar")).backgroundColor,
          prompt: getComputedStyle(document.querySelector(".terminal-window__prompt b")).color,
          promptBackground: getComputedStyle(document.querySelector(".terminal-window__prompt")).backgroundColor,
          number: getComputedStyle(number).color,
          numberSize: getComputedStyle(number).fontSize,
          numberWeight: getComputedStyle(number).fontWeight,
          stepTitle: getComputedStyle(title).color,
          commandDollar: getComputedStyle(document.querySelector("#rules .terminal-section__title span")).color,
          body: getComputedStyle(document.querySelector(".terminal-step p")).color,
          topDifference: Math.abs(number.getBoundingClientRect().top - title.getBoundingClientRect().top)
        }
      })()
    JS

    assert_equal "rgb(14, 14, 20)", publishing["background"]
    refute_equal "none", publishing["shadow"]
    assert_equal "rgb(122, 162, 247)", publishing["windowTitle"]
    assert_equal publishing["windowTitle"], publishing["titlebarRoute"]
    assert_equal publishing["windowTitleFont"], publishing["titlebarRouteFont"]
    assert_equal publishing["windowTitleSpacing"], publishing["titlebarRouteSpacing"]
    assert_equal "rgba(0, 0, 0, 0)", publishing["titlebarBackground"]
    assert_equal "rgb(122, 162, 247)", publishing["prompt"]
    assert_equal "rgba(0, 0, 0, 0)", publishing["promptBackground"]
    assert_equal "rgb(224, 175, 104)", publishing["number"]
    assert_equal "12px", publishing["numberSize"]
    assert_equal "400", publishing["numberWeight"]
    assert_equal "rgb(122, 162, 247)", publishing["stepTitle"]
    assert_equal "rgb(158, 206, 106)", publishing["commandDollar"]
    assert_equal "rgb(169, 177, 214)", publishing["body"]
    assert_in_delta 0, publishing["topDifference"], 0.5

    visit governance_path

    governance = page.evaluate_script <<~JS
      (() => ({
        numbers: [...document.querySelectorAll(".terminal-actions i")].map((node) => node.textContent.trim()),
        shadow: getComputedStyle(document.querySelector(".terminal-window")).boxShadow,
        number: getComputedStyle(document.querySelector(".terminal-actions i")).color,
        numberSize: getComputedStyle(document.querySelector(".terminal-actions i")).fontSize,
        numberWeight: getComputedStyle(document.querySelector(".terminal-actions i")).fontWeight,
        action: getComputedStyle(document.querySelector(".terminal-actions b")).color,
        commandDollar: getComputedStyle(document.querySelector("#powers .terminal-section__title span")).color,
        commandRule: getComputedStyle(document.querySelector("#powers .terminal-section__title"), "::after").display,
        body: getComputedStyle(document.querySelector(".terminal-actions span")).color
      }))()
    JS

    assert_equal [ "[1]", "[2]", "[3]", "[4]" ], governance["numbers"]
    assert_equal publishing["shadow"], governance["shadow"]
    assert_equal "rgb(224, 175, 104)", governance["number"]
    assert_equal publishing["numberSize"], governance["numberSize"]
    assert_equal publishing["numberWeight"], governance["numberWeight"]
    assert_equal "rgb(122, 162, 247)", governance["action"]
    assert_equal "rgb(158, 206, 106)", governance["commandDollar"]
    assert_equal "none", governance["commandRule"]
    assert_equal "rgb(169, 177, 214)", governance["body"]
  end

  test "compact publishing and governance titlebars stay on one typographic line" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 900, deviceScaleFactor: 1, mobile: false)

    {
      publishing_path => [ "Publishing guide", "publish.guide · read only" ],
      governance_path => [ "Governance", "learn.governance · read only" ]
    }.each do |path, (expected_title, expected_context)|
      visit path
      layout = page.evaluate_script <<~JS
        (() => {
          const titlebar = document.querySelector(".terminal-window__titlebar").getBoundingClientRect()
          const titleElement = document.querySelector(".terminal-window__titlebar strong")
          const contextElement = document.querySelector(".terminal-window__titlebar-context")
          const title = titleElement.getBoundingClientRect()
          const context = contextElement.getBoundingClientRect()
          return {
            title: titleElement.textContent.trim(),
            context: contextElement.textContent.trim(),
            sameFontSize: getComputedStyle(titleElement).fontSize === getComputedStyle(contextElement).fontSize,
            sameLine: Math.abs((title.top + title.bottom) / 2 - (context.top + context.bottom) / 2) < 0.5,
            distinct: title.right <= context.left,
            contained: title.left >= titlebar.left && context.right <= titlebar.right,
            overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          }
        })()
      JS
      assert_includes layout["title"], expected_title
      assert_equal expected_context, layout["context"]
      assert layout["sameFontSize"], path
      assert layout["sameLine"], path
      assert layout["distinct"], path
      assert layout["contained"], path
      assert_equal 0, layout["overflow"], path
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "terminal ANSI roles remain legible across every selectable theme" do
    visit governance_path
    page.execute_script <<~JS
      const style = document.createElement("style")
      style.textContent = "*, *::before, *::after { transition: none !important; }"
      document.head.append(style)
    JS

    failures = []
    ApplicationHelper::THEMES.each do |theme|
      page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
      ratios = page.evaluate_script <<~JS
        (() => {
          const canvas = document.createElement("canvas")
          canvas.width = canvas.height = 1
          const context = canvas.getContext("2d", { willReadFrequently: true })
          const rgb = (color) => {
            context.clearRect(0, 0, 1, 1)
            context.fillStyle = color
            context.fillRect(0, 0, 1, 1)
            return [...context.getImageData(0, 0, 1, 1).data].slice(0, 3)
          }
          const luminance = (color) => {
            const channels = rgb(color).map((value) => {
              value /= 255
              return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
            })
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
          }
          const background = getComputedStyle(document.querySelector(".terminal-window")).backgroundColor
          const ratio = (selector) => {
            const foreground = getComputedStyle(document.querySelector(selector)).color
            const first = luminance(foreground)
            const second = luminance(background)
            return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
          }
          return {
            body: ratio(".terminal-actions span"),
            action: ratio(".terminal-actions b"),
            number: ratio(".terminal-actions i"),
            heading: ratio(".terminal-window__main h1"),
            command: ratio(".terminal-section__title span"),
            activeTree: ratio(".terminal-window__tree a.is-active"),
            activeBranch: ratio(".terminal-window__tree a.is-active .terminal-window__tree-branch")
          }
        })()
      JS
      ratios.each do |role, ratio|
        threshold = role == "activeBranch" ? 3.0 : 4.5
        failures << "#{theme} #{role}=#{ratio.round(2)}" if ratio < threshold
      end
    end

    assert_empty failures, failures.join(", ")
  end

  test "terminal trees follow visible sections without drawing lines between branches" do
    visit publishing_path

    assert_selector ".terminal-window__tree a[href='#quick-start'].is-active[aria-current='location']"
    tree = page.evaluate_script <<~JS
      (() => {
        const nav = document.querySelector(".terminal-window__index-inner")
        const tree = document.querySelector(".terminal-window__tree")
        const branch = tree.querySelector("a.is-active .terminal-window__tree-branch")
        return {
          sticky: getComputedStyle(nav).position,
          interstitialLine: getComputedStyle(tree, "::before").content,
          glyph: branch.textContent,
          branch: getComputedStyle(branch).color,
          transition: getComputedStyle(branch).transitionDuration
        }
      })()
    JS
    assert_equal "sticky", tree["sticky"]
    assert_equal "none", tree["interstitialLine"]
    assert_equal "├─", tree["glyph"]
    assert_equal "rgb(158, 206, 106)", tree["branch"]
    assert_equal "0.16s", tree["transition"]

    find(".terminal-window__tree a[href='#namespace']").click
    assert_selector ".terminal-window__tree a[href='#namespace'].is-active[aria-current='location']"
    assert_no_selector ".terminal-window__tree a[href='#quick-start'][aria-current]"
    sleep 0.13

    page.execute_script <<~JS
      document.querySelector("#rules").scrollIntoView()
      window.dispatchEvent(new Event("scroll"))
    JS
    assert_selector ".terminal-window__tree a[href='#rules'].is-active[aria-current='location']"
    assert_equal "rgb(158, 206, 106)", page.evaluate_script(
      "getComputedStyle(document.querySelector(\".terminal-window__tree a[href='#quick-start'] .terminal-window__tree-branch\")).color"
    )

    page.execute_script("window.scrollTo(0, document.documentElement.scrollHeight)")
    assert_selector ".terminal-window__tree a[href='#trusted'].is-active[aria-current='location']"

    visit governance_path
    assert_selector ".terminal-window__tree a[href='#powers'].is-active[aria-current='location']"
    find(".terminal-window__tree a[href='#appeals']").click
    assert_selector ".terminal-window__tree a[href='#appeals'].is-active[aria-current='location']"
    find(".terminal-window__tree a[href='#transparency']").click
    assert_selector ".terminal-window__tree a[href='#transparency'].is-active[aria-current='location']"

    page.driver.browser.navigate.to(governance_url(anchor: "appeals"))
    assert_selector ".terminal-window__tree a[href='#appeals'].is-active[aria-current='location']"
    sleep 0.13
    page.execute_script("window.dispatchEvent(new Event('resize'))")
    assert_selector ".terminal-window__tree a[href='#appeals'].is-active[aria-current='location']"
  end
end

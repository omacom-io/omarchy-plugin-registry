require "application_system_test_case"

class AccountSurfacesSystemTest < ApplicationSystemTestCase
  setup do
    @user = User.create!(email_address: "account-ui@example.com", name: "Account UI")
    @publisher = Publisher.create!(name: "account-ui", kind: :personal)
    Membership.create!(publisher: @publisher, user: @user, role: :owner, founding: true,
      accepted_at: Time.current)
  end

  def sign_in_with_email_code
    visit new_session_path
    fill_in "email_address", with: @user.email_address
    click_button "Email me a code"
    assert_text "Enter your code"
    perform_enqueued_jobs
    fill_in "code", with: ActionMailer::Base.deliveries.last.subject[/\b(\d{6})\b/, 1]
    click_button "Sign in"
    assert_link "account/dashboard →", href: dashboard_path
  end

  test "account selections preserve themed shadows and aligned controls across page changes" do
    sign_in_with_email_code
    visit dashboard_path
    assert_selector ".terminal-window__titlebar", text: /account dashboard/i

    page.execute_script <<~JS
      window.__accountSurfaceAudit = (selectors) => ({
        surfaces: selectors.map((selector) => {
          const element = document.querySelector(selector)
          if (!element) return { selector, missing: true }
          const style = getComputedStyle(element)
          return { selector, shadow: style.boxShadow, clip: style.clipPath }
        }),
        clipped: [...document.querySelectorAll("*")].filter((element) => {
          const style = getComputedStyle(element)
          return style.boxShadow !== "none" && style.clipPath !== "none"
        }).map((element) => element.className || element.tagName),
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
      })
    JS

    audit = lambda do |label, selectors|
      selectors.each { |selector| assert_selector selector, visible: :all }
      result = page.evaluate_script("window.__accountSurfaceAudit(arguments[0])", selectors)
      failures = result["surfaces"].select do |surface|
        surface["missing"] || surface["shadow"] == "none" || surface["clip"] != "none"
      end
      assert_empty failures, "#{label}: #{failures.inspect}"
      assert_empty result["clipped"], "#{label}: shadow-bearing element is clipped"
      assert_equal 0, result["overflow"], "#{label}: horizontal overflow"
      result
    end

    dashboard_selectors = [
      ".terminal-window", ".account-panel", ".account-form input", ".account-form select"
    ]
    initial = audit.call("dashboard", dashboard_selectors)

    sizes = page.evaluate_script <<~JS
      [...document.querySelectorAll(".account-button")]
        .filter((button) => button.getClientRects().length)
        .map((button) => ({ width: button.getBoundingClientRect().width, height: button.getBoundingClientRect().height }))
    JS
    assert_operator sizes.map { |size| size["width"].round(2) }.uniq.size, :>, 1
    assert_operator sizes.map { |size| size["height"] }.max, :<=, 32
    token_fields = page.evaluate_script <<~JS
      (() => {
        const select = document.querySelector("#tokens select")
        const input = document.querySelector("#tokens input[type='text']")
        return {
          selectWidth: select.getBoundingClientRect().width,
          inputWidth: input.getBoundingClientRect().width,
          selectHeight: select.getBoundingClientRect().height,
          inputHeight: input.getBoundingClientRect().height,
          selectBackground: getComputedStyle(select).backgroundColor,
          inputBackground: getComputedStyle(input).backgroundColor,
          selectColor: getComputedStyle(select).color,
          inputColor: getComputedStyle(input).color
        }
      })()
    JS
    assert_in_delta token_fields["inputWidth"], token_fields["selectWidth"], 0.5
    assert_in_delta token_fields["inputHeight"], token_fields["selectHeight"], 0.5
    assert_equal token_fields["inputBackground"], token_fields["selectBackground"]
    assert_equal token_fields["inputColor"], token_fields["selectColor"]

    click_link "tokens", href: "#tokens"
    assert_selector "a[href='#tokens'].is-active[aria-current='location']"
    audit.call("dashboard tree selection", dashboard_selectors)

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    audit.call("dashboard theme picker", dashboard_selectors + [ ".theme-picker" ])
    find(".theme-picker__item[data-theme-value='white']").click
    page.driver.browser.action.send_keys(:enter).perform
    assert_selector "html[data-theme='white']", visible: :all
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    themed = audit.call("dashboard theme selection", dashboard_selectors)
    assert_not_equal initial.dig("surfaces", 1, "shadow"), themed.dig("surfaces", 1, "shadow")

    within(".terminal-window__titlebar") { click_link "security" }
    assert_current_path settings_two_factor_path
    assert_selector ".terminal-window__titlebar", text: /account security/i
    audit.call("account security", [ ".terminal-window", ".account-panel" ])

    page.go_back
    assert_current_path dashboard_path
    assert_selector ".terminal-window__titlebar", text: /account dashboard/i
    audit.call("security return", dashboard_selectors)

    click_link "Create an org"
    assert_current_path new_org_path
    assert_selector ".terminal-window__titlebar", text: /create organization/i
    org = audit.call("organization form",
      [ ".terminal-window", ".account-panel", ".account-form input" ])
    assert_operator page.evaluate_script(<<~JS), :<=, 32
      Math.max(...[...document.querySelectorAll(".account-form__actions .account-button")]
        .map((button) => button.getBoundingClientRect().height))
    JS
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    assert_not_equal "none", org.dig("surfaces", 1, "shadow")

    click_link "Cancel"
    assert_current_path dashboard_path
    assert_selector ".terminal-window__titlebar", text: /account dashboard/i
    assert_equal "#organizations", page.evaluate_script("window.location.hash")
    audit.call("organization return", dashboard_selectors)
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

  test "custom System ANSI colors reach the Account shell and native namespace menus" do
    9.times do |index|
      publisher = Publisher.create!(name: "account-org-#{index}", kind: :org)
      Membership.create!(publisher:, user: @user, role: :publisher, accepted_at: Time.current)
    end
    sign_in_with_email_code
    visit dashboard_path

    page.execute_script <<~JS
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='theme']"), "theme")
      controller.applyLiveTheme({ colors: {
        background: "#102030", foreground: "#f0f2f4", cursor: "#ffffff",
        color0: "#102030", color1: "#e06070", color2: "#70c080", color3: "#d0b060",
        color4: "#809ee0", color5: "#b080d0", color6: "#60b0c0", color7: "#d0d5dc",
        color8: "#687080", color9: "#f07080", color10: "#80d090", color11: "#e0c070",
        color12: "#90aef0", color13: "#c090e0", color14: "#70c0d0", color15: "#ffffff"
      } })
    JS

    find("nav[aria-label='Account sections'] a", text: "tokens").hover
    colors = page.evaluate_script <<~JS
      (() => {
        const menu = (select) => ({
          background: getComputedStyle(select).backgroundColor,
          option: getComputedStyle(select.querySelector("option")).backgroundColor,
          picker: getComputedStyle(select, "::picker(select)").backgroundColor,
          pickerArea: getComputedStyle(select, "::picker(select)").positionArea,
          pickerFallbacks: getComputedStyle(select, "::picker(select)").positionTryFallbacks,
          pickerMaxHeight: getComputedStyle(select, "::picker(select)").maxHeight,
          optionCount: select.options.length,
          customizable: CSS.supports("appearance: base-select"),
          arrow: getComputedStyle(select.nextElementSibling).color,
          height: select.getBoundingClientRect().height
        })
        return {
          title: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).color,
          titleFont: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).font,
          statusFont: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).font,
          titleSpacing: getComputedStyle(document.querySelector(".terminal-window__titlebar strong")).letterSpacing,
          statusSpacing: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).letterSpacing,
          statusColor: getComputedStyle(document.querySelector(".terminal-window__titlebar > span")).color,
          treeHover: getComputedStyle(document.querySelector("nav[aria-label='Account sections'] a[href='#tokens']")).color,
          credentials: menu(document.querySelector("#tokens select")),
          oidc: menu(document.querySelector("#trusted select"))
        }
      })()
    JS
    assert_equal "rgb(128, 158, 224)", colors["title"]
    assert_equal colors["title"], colors["statusColor"]
    assert_equal colors["titleFont"], colors["statusFont"]
    assert_equal colors["titleSpacing"], colors["statusSpacing"]
    assert_equal colors["title"], colors["treeHover"]
    %w[credentials oidc].each do |menu|
      assert_equal colors["title"], colors.dig(menu, "option")
      if colors.dig(menu, "customizable")
        assert_equal "rgb(16, 32, 48)", colors.dig(menu, "picker")
        assert_equal "end span-end", colors.dig(menu, "pickerArea")
        assert_equal "none", colors.dig(menu, "pickerFallbacks")
        assert_equal "240px", colors.dig(menu, "pickerMaxHeight")
        assert_equal 10, colors.dig(menu, "optionCount")
      end
      refute_equal "rgba(0, 0, 0, 0)", colors.dig(menu, "background")
      assert_equal colors["title"], colors.dig(menu, "arrow")
      assert_equal 38, colors.dig(menu, "height")
    end

    placement = page.evaluate_script <<~JS
      (() => {
        const select = document.querySelector("#trusted_publisher_name")
        select.scrollIntoView({ block: "end" })
        const before = window.scrollY
        const controller = window.Stimulus.getControllerForElementAndIdentifier(select.parentElement, "select-picker")
        controller.ensureSpace(select)
        return {
          delta: window.scrollY - before,
          room: window.innerHeight - select.getBoundingClientRect().bottom - 12
        }
      })()
    JS
    assert_operator placement["delta"], :>, 0
    assert_in_delta 247, placement["room"], 0.5
    find("#trusted_publisher_name").click
    page.driver.browser.action.send_keys(:escape).perform
  end

  test "account heading hierarchy and button hover contrast stay consistent across themes" do
    sign_in_with_email_code
    visit dashboard_path
    page.execute_script <<~JS
      const style = document.createElement("style")
      style.textContent = "*, *::before, *::after { transition: none !important; }"
      document.head.append(style)
    JS

    metadata_styles = page.evaluate_script <<~JS
      [...document.querySelectorAll(".account-panel__head")].map((heading) => {
        const style = getComputedStyle(heading)
        return [style.fontSize, style.fontWeight, style.letterSpacing, style.textTransform].join("|")
      })
    JS
    assert_equal 1, metadata_styles.uniq.size

    account_section_style = page.evaluate_script <<~JS
      (() => {
        const style = getComputedStyle(document.querySelector("#tokens .terminal-section__title"))
        return [style.fontSize, style.fontWeight, style.letterSpacing, style.textTransform].join("|")
      })()
    JS
    click_link "governance"
    assert_selector "#powers .terminal-section__title"
    governance_section_style = page.evaluate_script <<~JS
      (() => {
        const style = getComputedStyle(document.querySelector("#powers .terminal-section__title"))
        return [style.fontSize, style.fontWeight, style.letterSpacing, style.textTransform].join("|")
      })()
    JS
    assert_equal governance_section_style, account_section_style
    visit dashboard_path
    page.execute_script <<~JS
      const style = document.createElement("style")
      style.textContent = "*, *::before, *::after { transition: none !important; }"
      document.head.append(style)
    JS

    contrast_script = <<~JS
      (() => {
        const parse = (color) => color.match(/[\\d.]+/g).slice(0, 3).map(Number)
        const luminance = (color) => {
          const channels = parse(color).map((value) => {
            value /= 255
            return value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4
          })
          return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        const element = document.querySelector(arguments[0])
        const style = getComputedStyle(element)
        const foreground = luminance(style.color)
        const background = luminance(style.backgroundColor)
        return (Math.max(foreground, background) + 0.05) / (Math.min(foreground, background) + 0.05)
      })()
    JS

    failures = []
    ApplicationHelper::THEMES.each do |theme|
      page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
      {
        "create organization link" => "#organizations a.account-button",
        "mint token button" => "#tokens button.account-button",
        "sign out button" => "#session button.account-button",
        "namespace select" => "#tokens select"
      }.each do |label, selector|
        find(selector).hover
        ratio = page.evaluate_script(contrast_script, selector)
        failures << "#{theme} #{label}: #{ratio.round(2)}" if ratio < 4.5
      end
    end
    assert_empty failures, failures.join("\n")
  end

  test "account terminal remains aligned and elevated on a compact viewport" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 900, deviceScaleFactor: 1, mobile: false)
    sign_in_with_email_code
    visit dashboard_path

    dashboard = page.evaluate_script <<~JS
      (() => {
        const buttons = [...document.querySelectorAll(".account-button")]
          .filter((button) => button.getClientRects().length)
          .map((button) => button.getBoundingClientRect())
        const panel = document.querySelector(".account-panel")
        const titlebar = document.querySelector(".terminal-window__titlebar")
        const titleElement = titlebar.querySelector("strong")
        const actionElement = titlebar.querySelector(".terminal-window__titlebar-action")
        const title = titleElement.getBoundingClientRect()
        const action = actionElement.getBoundingClientRect()
        const actionArrow = actionElement.querySelector("span").getBoundingClientRect()
        return {
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          windowShadow: getComputedStyle(document.querySelector(".terminal-window")).boxShadow,
          panelShadow: getComputedStyle(panel).boxShadow,
          windowClip: getComputedStyle(document.querySelector(".terminal-window")).clipPath,
          panelClip: getComputedStyle(panel).clipPath,
          mobileNavPosition: getComputedStyle(document.querySelector(".mobile-nav")).position,
          mobileNavLinks: document.querySelectorAll(".mobile-nav a").length,
          mobileNavActive: document.querySelectorAll(".mobile-nav a.is-active").length,
          mobileNavTargets: [...document.querySelectorAll(".mobile-nav a")]
            .map((link) => link.getBoundingClientRect().height),
          titlebarTitle: titleElement.textContent.trim(),
          titlebarAction: actionElement.textContent.trim(),
          titlebarFontMatched: getComputedStyle(titleElement).fontSize === getComputedStyle(actionElement).fontSize,
          titlebarSingleLine: Math.abs((title.top + title.bottom) / 2 - (action.top + action.bottom) / 2) < 0.5 &&
            Math.abs((actionArrow.top + actionArrow.bottom) / 2 - (action.top + action.bottom) / 2) < 0.5,
          titlebarDistinct: title.right <= action.left,
          titlebarContextHidden: getComputedStyle(titlebar.querySelector(".terminal-window__titlebar-context")).display === "none",
          buttonWidths: buttons.map((button) => button.width.toFixed(2)),
          buttonHeights: buttons.map((button) => button.height.toFixed(2))
        }
      })()
    JS
    assert_equal 0, dashboard["overflow"]
    assert_not_equal "none", dashboard["windowShadow"]
    assert_not_equal "none", dashboard["panelShadow"]
    assert_equal "none", dashboard["windowClip"]
    assert_equal "none", dashboard["panelClip"]
    assert_equal "fixed", dashboard["mobileNavPosition"]
    assert_equal 4, dashboard["mobileNavLinks"]
    assert_equal 0, dashboard["mobileNavActive"]
    assert dashboard["mobileNavTargets"].all? { |height| height >= 44 }
    assert_equal "┌─ Account dashboard", dashboard["titlebarTitle"]
    assert_equal "security →", dashboard["titlebarAction"]
    assert dashboard["titlebarFontMatched"]
    assert dashboard["titlebarSingleLine"]
    assert dashboard["titlebarDistinct"]
    assert dashboard["titlebarContextHidden"]
    assert_operator dashboard["buttonWidths"].uniq.size, :>, 1
    assert_operator dashboard["buttonWidths"].map(&:to_f).max, :<, 180
    assert_operator dashboard["buttonHeights"].map(&:to_f).max, :<=, 32

    click_link "Create an org"
    assert_current_path new_org_path
    organization = page.evaluate_script <<~JS
      (() => ({
        overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
        panelShadow: getComputedStyle(document.querySelector(".account-panel")).boxShadow,
        widths: [...document.querySelectorAll(".account-form__actions .account-button")]
          .map((button) => button.getBoundingClientRect().width.toFixed(2))
      }))()
    JS
    assert_equal 0, organization["overflow"]
    assert_not_equal "none", organization["panelShadow"]
    assert_operator organization["widths"].uniq.size, :>, 1
    assert_operator organization["widths"].map(&:to_f).max, :<, 180
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end
end

require "application_system_test_case"

class IndexPickerSystemTest < ApplicationSystemTestCase
  setup do
    publisher = Publisher.create!(name: "acme", kind: :org)
    plugins = [
      { name: "alpha", summary: "Clock dashboard", category: "widgets", kinds: [ "bar-widget" ], tags: [ "bar" ] },
      { name: "beta", summary: "Volume control", category: "system", kinds: [ "audio-service" ], tags: [ "audio" ] },
      { name: "gamma", summary: "Clock colors", category: "appearance", kinds: [ "theme" ], tags: [ "clock" ] }
    ]

    plugins.each_with_index do |attributes, index|
      plugin = Plugin.create!(publisher:, latest_version: "1.0.0", downloads_count: 30 - index, **attributes)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: index.to_s * 64,
        size_bytes: 1024 * (index + 1), state: :published, published_at: Time.current)
    end
  end

  test "hero tree reveal uses live theme colors and preserves layout and shadows" do
    visit root_path(sort: "name")
    assert_selector ".hero__command", text: "registry@omarchy:~$ tree registry/"
    assert_no_text "Registry — signed public index"

    metrics = page.evaluate_script <<~JS
      (() => {
        const hero = document.querySelector(".hero--reveal")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(hero, "hero-reveal")
        controller.finish()
        hero.offsetWidth
        hero.classList.remove("is-complete")
        const command = document.querySelector(".hero__command-text")
        const commandLine = document.querySelector(".hero__command")
        const navigation = document.querySelector(".nav__path")
        const wordmark = document.querySelector(".hero__wm")
        const tile = wordmark.querySelector("rect")
        const fetch = document.querySelector(".fetch")
        const prompt = document.querySelector(".promptline--live")
        const delays = [...wordmark.querySelectorAll("rect")]
          .map((rect) => parseFloat(rect.style.getPropertyValue("--hero-reveal-delay")))
        const promptReveal = document.querySelector(".promptline__reveal")
        const promptWipe = promptReveal.getAnimations()
          .find((animation) => animation.animationName === "hero-content-wipe")
        promptWipe.pause()
        promptWipe.currentTime = 0
        const before = {
          commandAnimation: command.getAnimations()[0]?.animationName,
          commandOutAnimation: document.querySelector(".hero__command-visual").getAnimations()[0]?.animationName,
          tileAnimation: tile.getAnimations()[0]?.animationName,
          fetchAnimations: fetch.getAnimations({ subtree: true }).map((animation) => animation.animationName),
          headerAnimations: document.querySelector("header.band").getAnimations({ subtree: false })
            .map((animation) => animation.animationName),
          headerVisibility: getComputedStyle(document.querySelector("header.band")).visibility,
          promptWipeStart: getComputedStyle(promptReveal).clipPath,
          promptClip: getComputedStyle(prompt).clipPath,
          fetchClip: getComputedStyle(fetch).clipPath,
          wordmarkFilter: getComputedStyle(wordmark).filter,
          promptShadow: getComputedStyle(prompt).boxShadow,
          fetchShadow: getComputedStyle(fetch).boxShadow,
          wordmarkWidth: wordmark.getBoundingClientRect().width,
          wordmarkHeight: wordmark.getBoundingClientRect().height,
          navigationGap: commandLine.getBoundingClientRect().top - navigation.getBoundingClientRect().bottom,
          wordmarkGap: wordmark.getBoundingClientRect().top - commandLine.getBoundingClientRect().bottom,
          width: hero.offsetWidth,
          height: hero.offsetHeight,
          delayMinimum: Math.min(...delays),
          delayMaximum: Math.max(...delays)
        }
        document.documentElement.style.setProperty("--accent", "#123456")
        document.documentElement.style.setProperty("--terminal-cursor", "#654321")
        document.documentElement.style.setProperty("--ansi-02", "#abcdef")
        const themed = {
          host: getComputedStyle(document.querySelector(".hero__command-host")).color,
          cursor: getComputedStyle(document.querySelector(".hero__command-cursor")).backgroundColor,
          wordmark: getComputedStyle(wordmark).color
        }
        controller.finish()
        const after = {
          wordmarkFilter: getComputedStyle(wordmark).filter,
          promptShadow: getComputedStyle(prompt).boxShadow,
          fetchShadow: getComputedStyle(fetch).boxShadow,
          promptClip: getComputedStyle(prompt).clipPath,
          fetchClip: getComputedStyle(fetch).clipPath,
          width: hero.offsetWidth,
          height: hero.offsetHeight,
          commandWidth: command.getBoundingClientRect().width,
          tileOpacity: getComputedStyle(tile).fillOpacity,
          commandOpacity: getComputedStyle(document.querySelector(".hero__command-visual")).opacity,
          cursorOpacity: getComputedStyle(document.querySelector(".hero__command-cursor")).opacity,
          revealAnimations: hero.getAnimations({ subtree: true })
            .filter((animation) => animation.animationName.startsWith("hero-")).length,
          headerVisibility: getComputedStyle(document.querySelector("header.band")).visibility,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
        return { connected: Boolean(controller), before, themed, after }
      })()
    JS

    assert metrics["connected"]
    assert_equal "hero-command-type", metrics.dig("before", "commandAnimation")
    assert_equal "hero-command-out", metrics.dig("before", "commandOutAnimation")
    assert_equal "hero-wordmark-build", metrics.dig("before", "tileAnimation")
    assert_includes metrics.dig("before", "fetchAnimations"), "hero-content-rise"
    assert_includes metrics.dig("before", "fetchAnimations"), "hero-content-wipe"
    assert_includes metrics.dig("before", "headerAnimations"), "hero-navigation-fade"
    assert_equal "hidden", metrics.dig("before", "headerVisibility")
    assert_equal "inset(0px 100% 0px 0px)", metrics.dig("before", "promptWipeStart")
    assert_operator metrics.dig("before", "delayMinimum"), :>=, 560
    assert_operator metrics.dig("before", "delayMaximum"), :>, metrics.dig("before", "delayMinimum")
    assert_equal "none", metrics.dig("before", "promptClip")
    assert_equal "none", metrics.dig("before", "fetchClip")
    assert_not_equal "none", metrics.dig("before", "wordmarkFilter")
    assert_not_equal "none", metrics.dig("before", "promptShadow")
    assert_not_equal "none", metrics.dig("before", "fetchShadow")
    assert_equal 405, metrics.dig("before", "wordmarkWidth")
    assert_equal 95, metrics.dig("before", "wordmarkHeight")
    assert_operator metrics.dig("before", "navigationGap"), :>=, 40
    assert_operator metrics.dig("before", "wordmarkGap"), :>=, 40
    assert_equal "rgb(18, 52, 86)", metrics.dig("themed", "host")
    assert_equal "rgb(101, 67, 33)", metrics.dig("themed", "cursor")
    assert_equal "rgb(171, 205, 239)", metrics.dig("themed", "wordmark")
    assert_equal metrics.dig("before", "wordmarkFilter"), metrics.dig("after", "wordmarkFilter")
    assert_equal metrics.dig("before", "promptShadow"), metrics.dig("after", "promptShadow")
    assert_equal metrics.dig("before", "fetchShadow"), metrics.dig("after", "fetchShadow")
    assert_equal "none", metrics.dig("after", "promptClip")
    assert_equal "none", metrics.dig("after", "fetchClip")
    assert_equal metrics.dig("before", "width"), metrics.dig("after", "width")
    assert_equal metrics.dig("before", "height"), metrics.dig("after", "height")
    assert_operator metrics.dig("after", "commandWidth"), :>, 0
    assert_equal "1", metrics.dig("after", "tileOpacity")
    assert_equal "0", metrics.dig("after", "commandOpacity")
    assert_equal "0", metrics.dig("after", "cursorOpacity")
    assert_equal 0, metrics.dig("after", "revealAnimations")
    assert_equal "visible", metrics.dig("after", "headerVisibility")
    assert_equal 0, metrics.dig("after", "overflow")

    page.execute_script <<~JS
      document.querySelector(".hero--reveal").classList.remove("is-complete")
      document.dispatchEvent(new Event("turbo:before-cache"))
    JS
    assert_selector ".hero--reveal.is-complete"
    page.execute_script <<~JS
      document.querySelector(".hero--reveal").classList.remove("is-complete")
      window.dispatchEvent(new PageTransitionEvent("pageshow", { persisted: true }))
    JS
    assert_selector ".hero--reveal.is-complete"
  end

  test "hero tree reveal is immediately complete with reduced motion" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit root_path(sort: "name")

    assert_selector ".hero--reveal.is-complete"
    final = page.evaluate_script <<~JS
      (() => {
        const hero = document.querySelector(".hero--reveal")
        return {
          command: document.querySelector(".hero__command-text").getBoundingClientRect().width,
          tiles: [...document.querySelectorAll(".hero__wm rect")]
            .every((tile) => getComputedStyle(tile).fillOpacity === "1"),
          commandOpacity: getComputedStyle(document.querySelector(".hero__command-visual")).opacity,
          cursor: getComputedStyle(document.querySelector(".hero__command-cursor")).opacity,
          revealAnimations: hero.getAnimations({ subtree: true })
            .filter((animation) => animation.animationName.startsWith("hero-")).length,
          headerVisibility: getComputedStyle(document.querySelector("header.band")).visibility,
          headerAnimations: document.querySelector("header.band").getAnimations({ subtree: false })
            .filter((animation) => animation.animationName === "hero-navigation-fade").length,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert_operator final["command"], :>, 0
    assert final["tiles"]
    assert_equal "0", final["commandOpacity"]
    assert_equal "0", final["cursor"]
    assert_equal 0, final["revealAnimations"]
    assert_equal "visible", final["headerVisibility"]
    assert_equal 0, final["headerAnimations"]
    assert_equal 0, final["overflow"]
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "hero tree reveal preserves its compact mobile layout" do
    [ 320, 360 ].each do |width|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      visit root_path(sort: "name")

      layout = page.evaluate_script <<~JS
        (() => {
          const hero = document.querySelector(".hero--reveal")
          const controller = window.Stimulus.getControllerForElementAndIdentifier(hero, "hero-reveal")
          controller.finish()
          const completeHeight = hero.offsetHeight
          hero.offsetWidth
          hero.classList.remove("is-complete")
          hero.getAnimations({ subtree: true })
            .filter((animation) => animation.animationName.startsWith("hero-"))
            .forEach((animation) => { animation.pause(); animation.currentTime = 1200 })
          const command = document.querySelector(".hero__command").getBoundingClientRect()
          const visual = document.querySelector(".hero__command-visual").getBoundingClientRect()
          const copy = document.querySelector(".hero__copy").getBoundingClientRect()
          const fetch = document.querySelector(".fetch")
          const during = {
            height: hero.offsetHeight,
            commandFits: visual.left >= copy.left && visual.right <= copy.right + 0.5 && command.right <= copy.right + 0.5,
            fetchWidth: fetch.offsetWidth,
            fetchShadow: getComputedStyle(fetch).boxShadow,
            wordmarkWidth: document.querySelector(".hero__wm").getBoundingClientRect().width,
            wordmarkHeight: document.querySelector(".hero__wm").getBoundingClientRect().height,
            overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          }
          controller.finish()
          return {
            completeHeight,
            during,
            finalOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
            finalFetchOpacity: getComputedStyle(document.querySelector(".fetch__reveal")).opacity,
            finalCommandWidth: document.querySelector(".hero__command-text").getBoundingClientRect().width,
            markDisplay: getComputedStyle(document.querySelector(".fetch__mark")).display,
            rowsDisplay: getComputedStyle(document.querySelector(".fetch__rows")).display,
            promptDisplay: getComputedStyle(document.querySelector(".fetch__prompt")).display
          }
        })()
      JS

      assert layout.dig("during", "commandFits"), "command clipped at #{width}px"
      assert_operator layout.dig("during", "fetchWidth"), :>, 0
      assert_not_equal "none", layout.dig("during", "fetchShadow")
      assert_equal 243, layout.dig("during", "wordmarkWidth")
      assert_equal 57, layout.dig("during", "wordmarkHeight")
      assert_equal layout["completeHeight"], layout.dig("during", "height")
      assert_equal 0, layout.dig("during", "overflow")
      assert_equal 0, layout["finalOverflow"]
      assert_equal "1", layout["finalFetchOpacity"]
      assert_operator layout["finalCommandWidth"], :>, 0
      assert_equal "none", layout["markDisplay"]
      assert_equal "none", layout["rowsDisplay"]
      assert_equal "none", layout["promptDisplay"]
      assert_selector ".fetch__metric", text: /3\s+community plugins/i
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "hero wordmark keeps whole-pixel block sizes at responsive boundaries" do
    sizes = {
      1101 => [ 405, 95, 5 ],
      1100 => [ 324, 76, 4 ],
      961 => [ 324, 76, 4 ],
      960 => [ 324, 76, 4 ],
      761 => [ 324, 76, 4 ],
      760 => [ 243, 57, 3 ],
      320 => [ 243, 57, 3 ]
    }

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: sizes.keys.first, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(sort: "name")

    sizes.each do |width, (expected_width, expected_height, expected_cell)|
      page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
        width:, height: 900, deviceScaleFactor: 1, mobile: false)
      page.execute_script("window.dispatchEvent(new Event('resize'))")
      geometry = page.evaluate_script <<~JS
        (() => {
          const wordmark = document.querySelector(".hero__wm")
          const box = wordmark.getBoundingClientRect()
          const fetch = document.querySelector(".fetch").getBoundingClientRect()
          const timestamp = document.querySelector(".fetch__rprompt")
          const timestampBox = timestamp.getBoundingClientRect()
          const timeBox = timestamp.querySelector("time").getBoundingClientRect()
          const prompt = timestamp.parentElement
          const promptLeadBox = prompt.firstElementChild.getBoundingClientRect()
          const promptVisible = getComputedStyle(prompt).display !== "none"
          const sourceAligned = [...wordmark.querySelectorAll("rect")].every((rect) =>
            Number(rect.getAttribute("x")) % 51 === 0 &&
            Number(rect.getAttribute("y")) % 50 === 0 &&
            Number(rect.getAttribute("width")) % 51 === 0 &&
            Number(rect.getAttribute("height")) % 50 === 0
          )
          return {
            width: box.width,
            height: box.height,
            cellWidth: box.width / 81,
            cellHeight: box.height / 19,
            sourceAligned,
            promptVisible,
            timestampWrapped: promptVisible && timestampBox.top >= promptLeadBox.bottom - 0.5,
            timestampFits: !promptVisible || (
              timestampBox.left >= fetch.left && timestampBox.right <= fetch.right &&
              timeBox.left >= timestampBox.left && timeBox.right <= timestampBox.right
            ),
            overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          }
        })()
      JS

      assert_equal expected_width, geometry["width"], "wordmark width at #{width}px"
      assert_equal expected_height, geometry["height"], "wordmark height at #{width}px"
      assert_equal expected_cell, geometry["cellWidth"], "horizontal cell at #{width}px"
      assert_equal expected_cell, geometry["cellHeight"], "vertical cell at #{width}px"
      assert geometry["sourceAligned"], "source grid alignment at #{width}px"
      assert_equal width > 960, geometry["promptVisible"], "updated timestamp visibility at #{width}px"
      assert_equal width.between?(961, 1100), geometry["timestampWrapped"], "updated timestamp wrapping at #{width}px"
      assert geometry["timestampFits"], "updated timestamp fit at #{width}px"
      assert_equal 0, geometry["overflow"], "horizontal overflow at #{width}px"
    end
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Most Wanted and Recently Added names copy links while their cards open details" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__discoverySharedUrl = null
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
        writeText: async (value) => { window.__discoverySharedUrl = value }
      } })
    JS

    wanted_name = find(".recent-card--master .recent-card__name")
    wanted_url = wanted_name[:href]
    assert_equal "Copy link to acme/alpha", wanted_name["aria-label"]
    wanted_name.click
    assert_equal wanted_url, page.evaluate_script("window.__discoverySharedUrl")
    assert_current_path root_path(sort: "name")
    within(".recent-band") do
      assert_selector ".plugin-share__status.is-visible", text: "Plugin link copied"
    end

    recent_name = find(".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__name", match: :first)
    recent_url = recent_name[:href]
    assert_match(/\ACopy link to acme\//, recent_name["aria-label"])
    page.execute_script("window.__discoverySharedUrl = null")
    refute_equal "none", page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__track')).transform")
    recent_name.click
    assert_equal recent_url, page.evaluate_script("window.__discoverySharedUrl")
    assert_current_path root_path(sort: "name")
    within(".recent-stream") do
      assert_selector ".plugin-share__status.is-visible", text: "Plugin link copied"
    end
    assert page.evaluate_script <<~JS
      [...document.querySelectorAll(".plugin-share__status")].every((status) =>
        getComputedStyle(status).position === "fixed" &&
        !status.closest(".recent-band__layout, .recent-stream__layout"))
    JS

    page.execute_script <<~JS
      document.activeElement.blur()
      const animation = document.querySelector(".recent-stream__track").getAnimations()[0]
      animation.pause()
      animation.currentTime = 57_000
    JS
    duplicate_name = find(".recent-stream__group--duplicate .recent-stream__name", match: :first)
    duplicate_url = duplicate_name[:href]
    page.execute_script("window.__discoverySharedUrl = null")
    duplicate_name.click
    assert_equal duplicate_url, page.evaluate_script("window.__discoverySharedUrl")
    assert_current_path root_path(sort: "name")

    find(".recent-card--master .recent-card__open").click
    assert_current_path URI(wanted_url).path
  end

  test "the newest copy operation owns feedback across Browse and discovery" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__copyWrites = []
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
        writeText: (value) => new Promise((resolve, reject) => {
          window.__copyWrites.push({ value, resolve, reject })
        })
      } })
    JS

    find("body").send_keys("j")
    find("body").send_keys(:space)
    assert_equal 1, page.evaluate_script("window.__copyWrites.length")
    find(".recent-card--master .recent-card__name").click
    assert_equal 2, page.evaluate_script("window.__copyWrites.length")

    page.execute_script("window.__copyWrites[1].resolve()")
    assert_selector ".plugin-share__status.is-visible", text: "Plugin link copied", count: 1
    page.execute_script("window.__copyWrites[0].reject(new DOMException('Denied', 'NotAllowedError'))")
    sleep 0.05
    assert_no_selector ".index-picker__copy-status.is-visible"
    assert_selector ".plugin-share__status.is-visible", text: "Plugin link copied", count: 1
  end

  test "Recently Added resumes after returning from discovery details" do
    visit root_path(sort: "name")
    initial_shadow = page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__card')).boxShadow"
    )
    refute_equal "none", initial_shadow
    assert_equal "running", page.evaluate_script(
      "document.querySelector('.recent-stream__track').getAnimations()[0].playState")

    recent_open = find(".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__open", match: :first)
    recent_path = URI(recent_open[:href]).path
    recent_open.click
    assert_current_path recent_path
    page.go_back
    assert_current_path root_path(sort: "name")
    assert_selector ".recent-stream.is-enhanced:not(.is-hover-paused):not(.is-pointer-return)"
    assert_equal "running", page.evaluate_script(
      "document.querySelector('.recent-stream__track').getAnimations()[0].playState")
    assert_equal initial_shadow, page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__card')).boxShadow")

    wanted_open = find(".recent-card--master .recent-card__open")
    wanted_path = URI(wanted_open[:href]).path
    wanted_open.click
    assert_current_path wanted_path
    page.go_back
    assert_current_path root_path(sort: "name")
    assert_selector ".recent-stream.is-enhanced:not(.is-hover-paused):not(.is-pointer-return)"
    assert_equal "running", page.evaluate_script(
      "document.querySelector('.recent-stream__track').getAnimations()[0].playState")
    assert_equal initial_shadow, page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__card')).boxShadow")

    find(".hero").hover
    find(".recent-stream__viewport").hover
    assert_equal "paused", page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__track')).animationPlayState")
  end

  test "new focus or pointer activity keeps Recently Added paused during return recovery" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      const stream = document.querySelector(".recent-stream")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(stream, "recent-stream")
      sessionStorage.setItem("registry-discovery-pointer-return", "true")
      controller.resumeAfterPointerReturn()
      document.querySelector(".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__name").focus()
    JS
    sleep 0.3
    assert page.evaluate_script("document.activeElement.matches('.recent-stream__name')")
    assert page.evaluate_script("document.querySelector('.recent-stream').matches(':focus-within')")
    assert_equal 0, page.evaluate_script("document.querySelector('.recent-stream__track').getAnimations().length")

    page.execute_script <<~JS
      const stream = document.querySelector(".recent-stream")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(stream, "recent-stream")
      document.activeElement.blur()
      sessionStorage.setItem("registry-discovery-pointer-return", "true")
      controller.resumeAfterPointerReturn()
      stream.dispatchEvent(new PointerEvent("pointerenter"))
    JS
    sleep 0.3
    assert_selector ".recent-stream.is-hover-paused:not(.is-pointer-return)"
    assert_equal "paused", page.evaluate_script(
      "getComputedStyle(document.querySelector('.recent-stream__track')).animationPlayState")
  end

  test "Most Wanted stays stable until the visitor changes the master card" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      const index = document.querySelector("section[aria-labelledby='directory-title']")
      window.scrollTo(0, Math.max(index.offsetTop - 300, 0))
    JS

    measure = lambda do
      page.evaluate_script <<~JS
        (() => {
          const index = document.querySelector("section[aria-labelledby='directory-title']")
          const recent = document.querySelector(".recent-row")
          return {
            master: document.querySelector(".recent-card--master").textContent.trim(),
            scrollY: window.scrollY,
            indexTop: index.getBoundingClientRect().top + window.scrollY,
            recentHeight: recent.getBoundingClientRect().height
          }
        })()
      JS
    end

    before = measure.call
    sleep 0.5
    after = measure.call

    assert_equal before, after
  end

  test "Most Wanted controls rotate one master and four Browse-proportioned cards without growing the band" do
    publisher = Publisher.find_by!(name: "acme")
    2.times do |index|
      plugin = Plugin.create!(publisher:, name: "recent-extra-#{index}", summary: "Recent extra",
        latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 7).to_s * 64,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end
    visit root_path(sort: "name")

    previous = find("button.recent-band__step", text: "← previous")
    next_button = find("button.recent-band__step", text: "next →")
    assert_equal "ArrowLeft", previous["aria-keyshortcuts"]
    assert_equal "ArrowRight", next_button["aria-keyshortcuts"]
    assert_selector ".recent-band__count", text: /5.*\/ stats/m
    assert_selector ".recent-card", count: 5
    assert_selector ".recent-stack .recent-card", count: 4
    assert_equal page.evaluate_script("getComputedStyle(document.querySelector('.recent-band .boxtitle > h2')).fontSize"),
      page.evaluate_script("getComputedStyle(document.querySelector('.recent-band__count')).fontSize")
    assert_equal page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__range b')).color"),
      page.evaluate_script("getComputedStyle(document.querySelector('.recent-band__count small')).color")
    master_layout = page.evaluate_script <<~JS
      (() => {
        const master = document.querySelector(".recent-card--master")
        const art = master.querySelector(".recent-card__art")
        const summary = getComputedStyle(master.querySelector(".recent-card__summary"))
        return {
          leftAligned: getComputedStyle(master).textAlign === "left",
          artFromRight: getComputedStyle(art).objectPosition === "100% 50%",
          unfadedArt: getComputedStyle(art).maskImage === "none" && parseFloat(getComputedStyle(art).opacity) === 1,
          completeBars: [...document.querySelectorAll(".recent-card")].every((card) =>
            card.querySelector(".recent-card__visual") && card.querySelector(".recent-card__foot") &&
            card.querySelector(".recent-card__primary") && card.querySelector(".recent-card__secondary")),
          uniformBorders: new Set([...document.querySelectorAll(".recent-card")]
            .map((card) => getComputedStyle(card).borderTopWidth)).size === 1,
          singleLineSummaryFade: summary.whiteSpace === "nowrap" && summary.overflowX === "hidden" &&
            summary.maskImage.startsWith("linear-gradient"),
          recentHeight: document.querySelector(".recent-row").getBoundingClientRect().height,
          smallCardHeights: [...document.querySelectorAll(".recent-stack .recent-card")]
            .map((card) => card.offsetHeight),
          smallArtHeights: [...document.querySelectorAll(".recent-stack .recent-card__visual")]
            .map((art) => art.offsetHeight),
          smallColumns: new Set([...document.querySelectorAll(".recent-stack .recent-card")]
            .map((card) => card.offsetLeft)).size,
          smallMetadataOnly: [...document.querySelectorAll(".recent-stack .recent-card")].every((card) => {
            const signals = card.querySelector(".recent-card__signals")
            const artifact = card.querySelector(".recent-card__artifact")
            return card.querySelector(".recent-card__name") && card.querySelector(".recent-card__publisher") &&
              getComputedStyle(signals).display === "none" && getComputedStyle(artifact).display === "none" &&
              card.querySelector(".recent-card__foot").getBoundingClientRect().height <= 30
          })
        }
      })()
    JS
    assert master_layout["leftAligned"]
    assert master_layout["artFromRight"]
    assert master_layout["unfadedArt"]
    assert master_layout["completeBars"]
    assert master_layout["uniformBorders"]
    assert master_layout["singleLineSummaryFade"]
    assert_in_delta 392, master_layout["recentHeight"], 0.5
    assert_equal 1, master_layout["smallCardHeights"].map { |height| height.round(1) }.uniq.size
    assert master_layout["smallArtHeights"].all? { |height| height >= 120 }
    assert_equal 2, master_layout["smallColumns"]
    assert master_layout["smallMetadataOnly"]
    original = find(".recent-card--master .recent-card__name").text

    previous.click
    assert_not_equal original, find(".recent-card--master .recent-card__name").text
    rotated_metadata = page.evaluate_script <<~JS
      (() => {
        const master = document.querySelector(".recent-card--master")
        const small = [...document.querySelectorAll(".recent-stack .recent-card")]
        return {
          masterSignals: [...master.querySelectorAll('.recent-card__signals > span[aria-hidden="true"]')]
            .every((node) => getComputedStyle(node).display !== "none"),
          masterArtifact: [...master.querySelectorAll(".recent-card__artifact > span")]
            .every((node) => getComputedStyle(node).display !== "none"),
          smallDetailsHidden: small.every((card) =>
            [...card.querySelectorAll('.recent-card__signals > span[aria-hidden="true"], .recent-card__artifact > span')]
              .every((node) => getComputedStyle(node).display === "none"))
        }
      })()
    JS
    assert rotated_metadata.values.all?
    assert_equal "Show previous Most Wanted plugin", previous["aria-label"]

    next_button.click
    assert_equal original, find(".recent-card--master .recent-card__name").text

    next_button.send_keys(:arrow_left)
    assert_not_equal original, find(".recent-card--master .recent-card__name").text
    assert_no_selector ".recent-band__pause"

    aligned_right = page.evaluate_script <<~JS
      (() => {
        const title = document.querySelector(".recent-band .boxtitle").getBoundingClientRect()
        const controls = document.querySelector(".recent-band__controls").getBoundingClientRect()
        return Math.abs(title.right - controls.right) < 1
      })()
    JS
    assert aligned_right
    assert_current_path root_path(sort: "name")
  end

  test "mobile Most Wanted fits four preview cards below the master without exceeding the prior height" do
    publisher = Publisher.find_by!(name: "acme")
    2.times do |index|
      plugin = Plugin.create!(publisher:, name: "mobile-recent-#{index}", summary: "Mobile recent",
        latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 9).to_s(16) * 64,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(sort: "name")

    layout = page.evaluate_script <<~JS
      (() => {
        const cards = [...document.querySelectorAll(".recent-stack .recent-card")]
        return {
          recentHeight: document.querySelector(".recent-row").getBoundingClientRect().height,
          masterHeight: document.querySelector(".recent-card--master").offsetHeight,
          heights: cards.map((card) => card.offsetHeight),
          columns: new Set(cards.map((card) => card.offsetLeft)).size,
          wantedWidth: cards[0].offsetWidth,
          recentlyAddedWidth: document.querySelector(".recent-stream__card").offsetWidth,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert_equal 4, layout["heights"].length
    assert_equal 280, layout["masterHeight"]
    assert layout["heights"].all? { |height| height == 150 }
    assert_equal 2, layout["columns"]
    assert_in_delta layout["wantedWidth"], layout["recentlyAddedWidth"], 1
    assert_operator layout["recentHeight"], :<=, 608.5
    assert_equal 0, layout["overflow"]
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Recently Added image cards move right and pause for hover, focus, and controls" do
    plugin = Plugin.find_by!(name: "alpha")
    File.open(Rails.root.join("app/assets/images/themes/tokyo-night.webp")) do |preview|
      plugin.preview_card.attach(io: preview, filename: "alpha.webp", content_type: "image/webp")
    end
    plugin.update!(preview_meta: { "card" => { "width" => 1920, "height" => 1080 } })

    visit root_path(sort: "name")

    assert_selector ".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__card", count: 3
    assert_selector ".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__visual img", count: 1
    assert_selector ".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__fallback",
      text: "[ preview unavailable ]", count: 2
    presentation = page.evaluate_script <<~JS
      (() => {
        const wantedFallback = document.querySelector(".recent-stack .recent-card__art--fallback")
        const streamFallback = document.querySelector(".recent-stream__fallback")
        const fallbackProperties = [
          "alignItems", "backgroundColor", "backgroundImage", "color", "display", "filter",
          "fontFamily", "fontSize", "fontWeight", "justifyContent", "letterSpacing", "lineHeight",
          "paddingBottom", "paddingLeft", "paddingRight", "paddingTop", "textAlign"
        ]
        const wantedStyle = getComputedStyle(wantedFallback)
        const streamStyle = getComputedStyle(streamFallback)
        const textCenter = (element) => {
          const range = document.createRange()
          range.selectNodeContents(element)
          const rect = range.getBoundingClientRect()
          return rect.top + rect.height / 2
        }
        return {
          wanted: document.querySelector(".recent-stack .recent-card").offsetWidth,
          recentlyAdded: document.querySelector(".recent-stream__card").offsetWidth,
          shadow: getComputedStyle(document.querySelector(".recent-stream__card")).boxShadow,
          trendingAlignment: Math.abs(
            textCenter(document.querySelector(".recent-band__more")) -
            textCenter(document.querySelector(".recent-band__step"))
          ),
          fallbackMatches: fallbackProperties.every((property) => wantedStyle[property] === streamStyle[property]),
          copyCursors: [...document.querySelectorAll(
            ".index-picker__card-name, .recent-card__name, .recent-stream__name"
          )].map((link) => getComputedStyle(link).cursor)
        }
      })()
    JS
    assert_in_delta presentation["wanted"], presentation["recentlyAdded"], 1
    refute_equal "none", presentation["shadow"]
    assert_in_delta 0, presentation["trendingAlignment"], 0.1
    assert presentation["fallbackMatches"]
    assert_equal [ "copy" ], presentation["copyCursors"].uniq
    assert page.evaluate_script <<~JS
      (() => {
        const viewport = document.querySelector(".recent-stream__viewport")
        return getComputedStyle(viewport).maskImage.startsWith("linear-gradient") &&
          getComputedStyle(viewport, "::before").content === "none" &&
          getComputedStyle(viewport, "::after").content === "none"
      })()
    JS
    assert page.evaluate_script <<~JS
      [...document.querySelectorAll(".recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__card")]
        .every((card) => card.querySelector(".recent-stream__visual") &&
          getComputedStyle(card).boxShadow ===
            getComputedStyle(document.querySelector(".index-picker__layer-head")).boxShadow &&
          getComputedStyle(card, "::after").content === "none" &&
          card.querySelector(".recent-stream__primary > .recent-stream__name") &&
          card.querySelector(".recent-stream__secondary > .recent-stream__publisher") &&
          !card.querySelector("mark, b") &&
          card.querySelector(".recent-stream__body").children.length === 2 &&
          card.querySelector(".recent-stream__body").getBoundingClientRect().height <= 30 &&
          card.querySelector(".recent-stream__visual").getBoundingClientRect().height > 110)
    JS

    find(".hero").hover
    sleep 0.15
    first_x = page.evaluate_script("new DOMMatrix(getComputedStyle(document.querySelector('.recent-stream__track')).transform).m41")
    sleep 0.35
    moving = page.evaluate_script <<~JS
      (() => ({
        x: new DOMMatrix(getComputedStyle(document.querySelector(".recent-stream__track")).transform).m41,
        shadows: [...document.querySelectorAll(".recent-stream__card")]
          .map((card) => getComputedStyle(card).boxShadow)
      }))()
    JS
    assert_operator moving["x"], :>, first_x, "the stream should travel toward the right"
    assert moving["shadows"].all? { |shadow| shadow == presentation["shadow"] }, "moving cards must retain their shadows"

    find(".recent-stream__viewport").hover
    assert_equal "paused", page.evaluate_script("getComputedStyle(document.querySelector('.recent-stream__track')).animationPlayState")
    paused_shadows = page.evaluate_script(<<~JS, presentation["shadow"])
      [...document.querySelectorAll(".recent-stream__card")]
        .every((card) => getComputedStyle(card).boxShadow === arguments[0])
    JS
    assert paused_shadows, "paused cards must retain their shadows"
    page.execute_script("document.querySelector('.recent-stream__group:not(.recent-stream__group--duplicate) .recent-stream__open').focus()")
    focused_layout = page.evaluate_script <<~JS
      (() => {
        const card = document.activeElement.getBoundingClientRect()
        const viewport = document.querySelector(".recent-stream__viewport").getBoundingClientRect()
        return {
          paused: getComputedStyle(document.querySelector(".recent-stream__track")).animationName === "none",
          unfaded: getComputedStyle(document.querySelector(".recent-stream__viewport")).maskImage === "none",
          visible: card.left >= viewport.left && card.right <= viewport.right,
          duplicateHidden: getComputedStyle(document.querySelector(".recent-stream__group--duplicate")).display === "none"
        }
      })()
    JS
    assert focused_layout["paused"]
    assert focused_layout["unfaded"]
    assert focused_layout["visible"]
    assert focused_layout["duplicateHidden"]

    toggle = find("button.recent-stream__toggle", visible: true)
    assert_equal page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__sort summary')).columnGap"),
      page.evaluate_script("getComputedStyle(document.querySelector('.recent-stream__toggle')).columnGap")
    toggle.click
    assert_equal "true", toggle["aria-pressed"]
    assert_equal "Resume Recently Added", toggle["aria-label"]
    assert page.evaluate_script("document.querySelector('.recent-stream').classList.contains('is-paused')")

    fallback = page.evaluate_script <<~JS
      (() => {
        const stream = document.querySelector(".recent-stream")
        stream.classList.remove("is-enhanced")
        const result = {
          scrollable: getComputedStyle(stream.querySelector(".recent-stream__viewport")).overflowX === "auto",
          duplicateHidden: getComputedStyle(stream.querySelector(".recent-stream__group--duplicate")).display === "none"
        }
        stream.classList.add("is-enhanced")
        return result
      })()
    JS
    assert fallback.values.all?
  end

  test "discovery motion follows reduced-motion changes while the page is open" do
    visit root_path(sort: "name")
    previous = find("button.recent-band__step", text: "← previous")

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    previous.click
    assert page.evaluate_script("[...document.querySelectorAll('.recent-card')].every((card) => card.getAnimations().length === 0)")
    assert_selector "button.recent-stream__toggle[hidden]", visible: :all
    assert page.evaluate_script("document.querySelector('.recent-stream__track').getAnimations().length === 0")
    assert page.evaluate_script("getComputedStyle(document.querySelector('.recent-stream__group--duplicate')).display === 'none'")
    assert page.evaluate_script("getComputedStyle(document.querySelector('.recent-stream__viewport')).maskImage === 'none'")

    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "no-preference" } ])
    previous.click
    assert page.evaluate_script("[...document.querySelectorAll('.recent-card')].some((card) => card.getAnimations().length > 0)")
    assert_selector "button.recent-stream__toggle", visible: true
    assert page.evaluate_script("document.querySelector('.recent-stream__track').getAnimations().length > 0")
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "Tokyo Night is the default palette and White remains persistently selectable" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      localStorage.removeItem("registry-theme")
      localStorage.setItem("registry-theme-mode", "manual")
      localStorage.removeItem("registry-system-theme")
      localStorage.removeItem("registry-theme-override-revision")
    JS
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click

    palette = page.evaluate_script <<~JS
      (() => {
        const style = getComputedStyle(document.documentElement)
        const fetchBar = document.querySelector(".fetch__bar")
        fetchBar.innerHTML = "[---<i>C</i>o-o]"
        return {
          theme: document.documentElement.dataset.theme,
          background: style.getPropertyValue("--bg").trim(),
          accent: style.getPropertyValue("--accent").trim(),
          green: style.getPropertyValue("--success").trim(),
          yellow: style.getPropertyValue("--ansi-03").trim(),
          magenta: style.getPropertyValue("--ansi-05").trim(),
          brightBlack: style.getPropertyValue("--ansi-08").trim(),
          foreground: style.getPropertyValue("--text-muted").trim(),
          brightForeground: style.getPropertyValue("--text").trim(),
          fetchMark: getComputedStyle(document.querySelector(".fetch__logo")).color,
          fetchMarkFloating: getComputedStyle(document.querySelector(".fetch__logo")).filter !== "none",
          fetchCount: getComputedStyle(document.querySelector(".fetch__head strong")).color,
          fetchLabel: getComputedStyle(document.querySelector(".fetch__head span")).color,
          fetchKey: getComputedStyle(document.querySelector(".fetch__row .k")).color,
          fetchValue: getComputedStyle(document.querySelector(".fetch__row b")).color,
          fetchBar: getComputedStyle(fetchBar).color,
          fetchPacman: getComputedStyle(fetchBar.querySelector("i")).color,
          fetchBackground: getComputedStyle(document.querySelector(".fetch")).backgroundColor,
          promptRegistry: getComputedStyle(document.querySelector(".promptline__host")).color,
          fetchRegistry: getComputedStyle(document.querySelector(".fetch__prompt b")).color,
          fetchCursor: getComputedStyle(document.querySelector(".fetch__cursor")).backgroundColor,
          browseCount: getComputedStyle(document.querySelector(".index-browse__range strong")).color,
          browseSuffix: getComputedStyle(document.querySelector(".index-browse__range b")).color,
          browseDollar: getComputedStyle(document.querySelector(".index-browse__sort summary i")).color,
          sortArrow: getComputedStyle(document.querySelector(".index-browse__sort summary > b")).color,
          wantedCount: getComputedStyle(document.querySelector(".recent-band__count strong")).color,
          wantedSuffix: getComputedStyle(document.querySelector(".recent-band__count small")).color,
          wantedDollar: getComputedStyle(document.querySelector(".recent-band__more span")).color,
          wantedArrows: [...document.querySelectorAll(".recent-band__step-symbol")]
            .map((symbol) => getComputedStyle(symbol).color),
          recentCount: getComputedStyle(document.querySelector(".recent-stream__count strong")).color,
          recentSuffix: getComputedStyle(document.querySelector(".recent-stream__count small")).color,
          recentDollar: getComputedStyle(document.querySelector(".recent-stream__more span")).color,
          pauseSymbol: getComputedStyle(document.querySelector(".recent-stream__toggle-symbol")).color,
          filterLabel: getComputedStyle(document.querySelector(".index-search__filter-toggle")).color,
          filterCount: getComputedStyle(document.querySelector(".index-picker__category strong")).color,
          browseNav: getComputedStyle(document.querySelector(".index-picker__status-item > b")).color,
          pageArrows: [...document.querySelectorAll(".index-picker__pagination > a")]
            .map((arrow) => getComputedStyle(arrow).color),
          searchCount: getComputedStyle(document.querySelector(".index-search__result")).color,
          searchCursor: getComputedStyle(document.querySelector(".index-search__cursor")).backgroundColor,
          searchCaret: getComputedStyle(document.querySelector("input[name='q']")).caretColor,
          wordmark: getComputedStyle(document.querySelector(".hero__wm")).color,
          wordmarkFloating: getComputedStyle(document.querySelector(".hero__wm")).filter !== "none",
          footerWordmark: getComputedStyle(document.querySelector(".statusfoot__omarchy-wordmark")).backgroundColor,
          footerWordmarkFloating: getComputedStyle(document.querySelector(".statusfoot__omarchy-link")).filter !== "none",
          footerMaskUnfiltered: getComputedStyle(document.querySelector(".statusfoot__omarchy-wordmark")).filter === "none",
          themeSymbol: getComputedStyle(document.querySelector(".theme-toggle i")).backgroundColor,
          themeText: getComputedStyle(document.querySelector(".theme-toggle")).color,
          themeName: getComputedStyle(document.querySelector(".theme-toggle__label")).color,
          windowsShadowed: [ ".theme-picker", ".fetch", ".index-search" ]
            .every((selector) => getComputedStyle(document.querySelector(selector)).boxShadow ===
              getComputedStyle(document.querySelector(".index-search")).boxShadow),
          tilesShadowed: [
            ".promptline", ".recent-card", ".recent-stream__card", ".index-picker__layer-head",
            ".index-picker__card", ".index-picker__status"
          ].every((selector) => getComputedStyle(document.querySelector(selector)).boxShadow ===
            getComputedStyle(document.querySelector(".index-picker__layer-head")).boxShadow),
          controlsShadowed: [
            ".index-search__result", ".index-search__form kbd", ".index-search__reset", ".index-search__clear",
            ".index-search__filter-toggle", ".index-picker__filter-option"
          ].every((selector) => getComputedStyle(document.querySelector(selector)).boxShadow ===
            getComputedStyle(document.querySelector(".index-search__form kbd")).boxShadow),
          browseSeparate: getComputedStyle(document.querySelector(".index-browse-stack")).boxShadow === "none",
          floatsShadowed: [
            ".index-search__suggestions", ".index-browse__sort-options", ".index-picker__key-tooltip",
            ".index-picker__copy-status"
          ].every((selector) => getComputedStyle(document.querySelector(selector)).boxShadow ===
            getComputedStyle(document.querySelector(".index-browse__sort-options")).boxShadow),
          elevationDiffers: new Set([
            getComputedStyle(document.querySelector(".index-search")).boxShadow,
            getComputedStyle(document.querySelector(".index-picker__layer-head")).boxShadow,
            getComputedStyle(document.querySelector(".index-browse__sort-options")).boxShadow
          ]).size === 3
        }
      })()
    JS
    assert_equal({
      "theme" => "tokyo-night",
      "background" => "#1a1b26",
      "accent" => "#7aa2f7",
      "green" => "#9ece6a",
      "yellow" => "#e0af68",
      "magenta" => "#ad8ee6",
      "brightBlack" => "#414868",
      "foreground" => "#a9b1d6",
      "brightForeground" => "#c0caf5",
      "fetchMark" => "rgb(158, 206, 106)",
      "fetchMarkFloating" => true,
      "fetchCount" => "rgb(247, 118, 142)",
      "fetchLabel" => "rgb(169, 177, 214)",
      "fetchKey" => "rgb(122, 162, 247)",
      "fetchValue" => "rgb(192, 202, 245)",
      "fetchBar" => "rgb(173, 142, 230)",
      "fetchPacman" => "rgb(224, 175, 104)",
      "fetchBackground" => "rgb(26, 27, 38)",
      "promptRegistry" => "rgb(68, 157, 171)",
      "fetchRegistry" => "rgb(68, 157, 171)",
      "fetchCursor" => "rgb(192, 202, 245)",
      "browseCount" => "rgb(158, 206, 106)",
      "browseSuffix" => "rgb(68, 157, 171)",
      "browseDollar" => "rgb(158, 206, 106)",
      "sortArrow" => "rgb(158, 206, 106)",
      "wantedCount" => "rgb(158, 206, 106)",
      "wantedSuffix" => "rgb(68, 157, 171)",
      "wantedDollar" => "rgb(158, 206, 106)",
      "wantedArrows" => [ "rgb(158, 206, 106)", "rgb(158, 206, 106)" ],
      "recentCount" => "rgb(158, 206, 106)",
      "recentSuffix" => "rgb(68, 157, 171)",
      "recentDollar" => "rgb(158, 206, 106)",
      "pauseSymbol" => "rgb(158, 206, 106)",
      "filterLabel" => "rgb(158, 206, 106)",
      "filterCount" => "rgb(158, 206, 106)",
      "browseNav" => "rgb(158, 206, 106)",
      "pageArrows" => [ "rgb(158, 206, 106)", "rgb(158, 206, 106)" ],
      "searchCount" => "rgb(247, 118, 142)",
      "searchCursor" => "rgb(192, 202, 245)",
      "searchCaret" => "rgb(192, 202, 245)",
      "wordmark" => "rgb(158, 206, 106)",
      "wordmarkFloating" => true,
      "footerWordmark" => "rgb(158, 206, 106)",
      "footerWordmarkFloating" => true,
      "footerMaskUnfiltered" => true,
      "themeSymbol" => "rgb(158, 206, 106)",
      "themeText" => "rgb(158, 206, 106)",
      "themeName" => "rgb(158, 206, 106)",
      "windowsShadowed" => true,
      "tilesShadowed" => true,
      "controlsShadowed" => true,
      "browseSeparate" => true,
      "floatsShadowed" => true,
      "elevationDiffers" => true
    }, palette)
    assert_selector ".theme-toggle", text: /theme=\s*tokyo-night/

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    2.times { page.driver.browser.action.send_keys(:arrow_right).perform }
    page.driver.browser.action.send_keys(:enter).perform
    assert_equal "white", page.evaluate_script("localStorage.getItem('registry-theme')")
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")

    visit root_path(sort: "name")
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    assert_selector ".theme-toggle", text: /theme=\s*white/
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

  test "separate floating surfaces derive their shadows from each theme" do
    visit root_path(sort: "name")

    shadows = %w[tokyo-night white gruvbox].to_h do |theme|
      page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
      [ theme, page.evaluate_script(<<~JS) ]
        (() => ({
          window: getComputedStyle(document.querySelector(".index-search")).boxShadow,
          tile: getComputedStyle(document.querySelector(".index-picker__card")).boxShadow,
          recent: getComputedStyle(document.querySelector(".recent-stream__card")).boxShadow,
          control: getComputedStyle(document.querySelector(".index-search__form kbd")).boxShadow,
          floating: getComputedStyle(document.querySelector(".index-browse__sort-options")).boxShadow,
          mark: getComputedStyle(document.querySelector(".hero__wm")).filter,
          footerMark: getComputedStyle(document.querySelector(".statusfoot__omarchy-link")).filter,
          footerMask: getComputedStyle(document.querySelector(".statusfoot__omarchy-wordmark")).filter,
          browseSeparate: getComputedStyle(document.querySelector(".index-browse-stack")).boxShadow === "none"
        }))()
      JS
    end

    shadows.each_value do |theme_shadows|
      %w[window tile recent control floating mark footerMark].each { |role| refute_equal "none", theme_shadows[role] }
      assert_equal "none", theme_shadows["footerMask"]
      assert_equal theme_shadows["tile"], theme_shadows["recent"]
      assert_equal 3, theme_shadows.values_at("window", "tile", "floating").uniq.size
      assert theme_shadows["browseSeparate"]
    end
    %w[window tile recent floating mark footerMark].each do |role|
      assert_equal 3, shadows.values.map { |value| value[role] }.uniq.size
    end
  end

  test "header controls match section-heading type and the footer mark keeps its shadow across pages" do
    visit root_path(sort: "name")

    sizes = page.evaluate_script <<~JS
      (() => ({
        heading: getComputedStyle(document.querySelector(".recent-band .boxtitle h2")).fontSize,
        section: getComputedStyle(document.querySelector(".nav__section")).fontSize,
        account: getComputedStyle(document.querySelector(".nav__account")).fontSize,
        theme: getComputedStyle(document.querySelector(".theme-toggle")).fontSize,
        footerShadow: getComputedStyle(document.querySelector(".statusfoot__omarchy-link")).filter
      }))()
    JS
    assert_equal sizes["heading"], sizes["section"]
    assert_equal sizes["heading"], sizes["account"]
    assert_equal sizes["heading"], sizes["theme"]
    refute_equal "none", sizes["footerShadow"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 600, height: 900, deviceScaleFactor: 1, mobile: false)
    responsive_sizes = page.evaluate_script <<~JS
      (() => ({
        heading: getComputedStyle(document.querySelector(".recent-band .boxtitle h2")).fontSize,
        section: getComputedStyle(document.querySelector(".nav__section")).fontSize,
        account: getComputedStyle(document.querySelector(".nav__account")).fontSize,
        theme: getComputedStyle(document.querySelector(".theme-toggle")).fontSize
      }))()
    JS
    assert_equal [ responsive_sizes["heading"] ], responsive_sizes.values.uniq
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")

    click_link "governance"
    assert_current_path governance_path
    assert_selector ".terminal-window__titlebar", text: /governance/i
    assert_equal sizes["footerShadow"], page.evaluate_script(
      'getComputedStyle(document.querySelector(".statusfoot__omarchy-link")).filter'
    )

    click_link "publishing"
    assert_current_path publishing_path
    assert_selector ".terminal-window__titlebar", text: /publishing guide/i
    assert_equal sizes["footerShadow"], page.evaluate_script(
      'getComputedStyle(document.querySelector(".statusfoot__omarchy-link")).filter'
    )
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "shadowed boxes remain elevated through every discovery selection and page transition" do
    publisher = Publisher.find_by!(name: "acme")
    7.times do |index|
      plugin = Plugin.create!(publisher:, name: "extra-#{index}", summary: "Extra plugin #{index}",
        category: "utilities", kinds: [ "utility" ], tags: [ "productivity" ],
        latest_version: "1.0.0", downloads_count: 20 - index)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: format("%064x", index + 10),
        size_bytes: 2048, state: :published, published_at: Time.current)
    end

    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector(".hero--reveal"), "hero-reveal"
      ).finish()
      window.__registryShadowAudit = (selectors) => {
        const failures = selectors.flatMap((selector) => {
          const element = document.querySelector(selector)
          if (!element) return [`${selector}:missing`]
          const style = getComputedStyle(element)
          const parentOverflow = getComputedStyle(element.parentElement).overflow
          const errors = []
          if (style.boxShadow === "none") errors.push(`${selector}:no-shadow`)
          if (style.clipPath !== "none") errors.push(`${selector}:self-clipped`)
          if (["hidden", "clip"].includes(parentOverflow)) errors.push(`${selector}:parent-${parentOverflow}`)
          return errors
        })
        return {
          failures,
          clippedShadowElements: [...document.querySelectorAll("*")].filter((element) => {
            const style = getComputedStyle(element)
            return style.boxShadow !== "none" && style.clipPath !== "none"
          }).map((element) => element.className || element.tagName),
          statusShadow: getComputedStyle(document.querySelector(".index-picker__status")).boxShadow,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      }
    JS

    expected = [
      ".fetch", ".promptline--live", ".index-search", ".index-picker__layer-head",
      ".index-picker__card", ".index-picker__status"
    ]
    audit = lambda do |label, selectors = expected|
      result = page.evaluate_script("window.__registryShadowAudit(arguments[0])", selectors)
      assert_empty result["failures"], "#{label}: #{result['failures'].join(', ')}"
      assert_empty result["clippedShadowElements"], "#{label}: shadow and clip-path share an element"
      assert_equal 0, result["overflow"], "#{label}: horizontal overflow"
      result
    end

    initial = audit.call("initial")

    find(".recent-band__step", match: :first).click
    find(".recent-stream__toggle").click
    audit.call("discovery controls")

    find(".index-browse__sort summary").click
    assert_selector ".index-browse__sort.is-open"
    audit.call("sort menu", expected + [ ".index-browse__sort-options" ])
    find("body").send_keys(:escape)

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    audit.call("theme picker", expected + [ ".theme-picker" ])
    find(".theme-picker__item[data-theme-value='white']").click
    page.driver.browser.action.send_keys(:enter).perform
    assert_equal "white", page.evaluate_script("document.documentElement.dataset.theme")
    themed = audit.call("theme selection")
    assert_not_equal initial["statusShadow"], themed["statusShadow"]

    search = find("input[name='q']")
    search.set("clock")
    assert_selector ".index-picker__row", count: 2
    audit.call("live search")
    search.set("")
    assert_selector ".index-picker__row", count: HomeController::PER_PAGE

    find("a[aria-label='Next nine plugin results']").click
    assert_selector ".index-picker__row", count: 1, text: "gamma"
    assert_equal "2", find("input[aria-label='Jump to result page']").value
    audit.call("next page")

    find(".index-picker__card-open", match: :first).click
    assert_current_path %r{/plugins/acme/}
    page.go_back
    assert_equal "2", find("input[aria-label='Jump to result page']").value
    audit.call("detail return")

    click_link "governance"
    assert_selector ".terminal-window"
    governance_shadow = page.evaluate_script("getComputedStyle(document.querySelector('.terminal-window')).boxShadow")
    assert_not_equal "none", governance_shadow
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.terminal-window')).clipPath")

    click_link "publishing"
    assert_selector ".terminal-window"
    assert_equal governance_shadow,
      page.evaluate_script("getComputedStyle(document.querySelector('.terminal-window')).boxShadow")
    assert_equal "none", page.evaluate_script("getComputedStyle(document.querySelector('.terminal-window')).clipPath")
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

  test "ANSI UI roles remain legible across every selectable theme" do
    contrast_script = <<~JS
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
        const contrast = (foreground, background) => {
          const first = luminance(foreground)
          const second = luminance(background)
          return (Math.max(first, second) + 0.05) / (Math.min(first, second) + 0.05)
        }
        const ratio = (foreground, background, property = "color") => contrast(
          getComputedStyle(document.querySelector(foreground))[property],
          getComputedStyle(document.querySelector(background)).backgroundColor
        )
        const tickerElement = document.querySelector("[data-controller~='ticker']")
        const ticker = window.Stimulus.getControllerForElementAndIdentifier(tickerElement, "ticker")
        ticker.readColors()
        const tickerBackground = getComputedStyle(tickerElement.closest(".promptline")).backgroundColor
        return {
          searchText: ratio(".index-search__result", ".index-search"),
          searchBorder: ratio(".index-search__result", ".index-search", "borderTopColor"),
          filterLabel: ratio(".index-search__filter-toggle.is-active", ".index-search__filter-toggle.is-active"),
          category: ratio(".index-picker__category.is-active", ".index-picker__layer-head"),
          categoryCount: ratio(".index-picker__category.is-active strong", ".index-picker__layer-head"),
          selectedName: ratio(".index-picker__row.is-selected .index-picker__card-name", ".index-picker__row.is-selected"),
          themeToggle: ratio(".theme-toggle", "body"),
          tickerText: contrast(ticker.colors.text, tickerBackground),
          tickerNumber: contrast(ticker.colors.ansi02, tickerBackground)
        }
      })()
    JS

    visit root_path(sort: "name")
    page.execute_script <<~JS
      const style = document.createElement("style")
      style.textContent = "*, *::before, *::after { transition: none !important; }"
      document.head.append(style)
      document.querySelector(".index-search__filter-toggle").click()
      document.querySelector(".index-picker__category").classList.add("is-active")
      document.querySelector(".index-picker__row").classList.add("is-selected")
    JS
    failures = []
    ApplicationHelper::THEMES.each do |theme|
      page.execute_script("document.documentElement.dataset.theme = arguments[0]", theme)
      page.evaluate_script(contrast_script).each do |role, ratio|
        threshold = role == "searchBorder" ? 3.0 : 4.5
        failures << "#{theme} #{role}=#{ratio.round(2)}" if ratio < threshold
      end
    end
    assert_empty failures, failures.join(", ")
  end

  test "j and k select plugins globally while text inputs keep normal typing" do
    visit root_path(sort: "name")

    assert_no_selector ".index-picker__row.is-selected"

    search = find("input[name='q']")
    search.send_keys("j")
    assert_equal "j", search.value
    search.send_keys(:escape)
    assert_no_selector ".index-picker[aria-busy='true']"
    assert_selector ".index-picker__row", count: 3
    assert_current_path root_path(sort: "name")

    find("body").send_keys("j")
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    find("body").send_keys("j")
    assert_selector ".index-picker__row.is-selected", text: "beta"

    find("body").send_keys("k")
    assert_selector ".index-picker__row.is-selected", text: "alpha"

    find("body").send_keys("j")
    assert_selector ".index-picker__row.is-selected", text: "beta"
    find("body").send_keys(:enter)
    assert_current_path plugin_path("acme", "beta")
  end

  test "mouse hover stays soft and only keyboard movement activates a card" do
    visit root_path(sort: "name")
    assert_no_selector ".index-picker__row.is-selected"

    find(".index-picker__row", text: "beta").hover
    assert_no_selector ".index-picker__row.is-selected"
    hover_colors = page.evaluate_script <<~JS
      (() => ({
        hovered: getComputedStyle([...document.querySelectorAll(".index-picker__row")]
          .find((row) => row.dataset.name === "beta")).borderTopColor,
        accent: getComputedStyle(document.querySelector(".theme-toggle i")).backgroundColor,
        idle: getComputedStyle([...document.querySelectorAll(".index-picker__row")]
          .find((row) => row.dataset.name === "gamma")).borderTopColor
      }))()
    JS
    refute_equal hover_colors["accent"], hover_colors["hovered"]
    refute_equal hover_colors["idle"], hover_colors["hovered"]

    find("body").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    selected_color = page.evaluate_script(
      "getComputedStyle(document.querySelector('.index-picker__row.is-selected')).borderTopColor")
    assert_equal hover_colors["accent"], selected_color
    assert_equal "rgb(158, 206, 106)", selected_color

    find(".index-picker__row", text: "beta").hover
    pointer_selection = page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector(".index-picker")
        const selected = document.querySelector(".index-picker__row.is-selected")
        return { pointerMode: picker.classList.contains("is-pointer-mode"),
          border: getComputedStyle(selected).borderTopColor,
          outline: getComputedStyle(selected).outlineStyle,
          linkOutline: getComputedStyle(selected.querySelector(".index-picker__card-open")).outlineStyle }
      })()
    JS
    assert pointer_selection["pointerMode"]
    refute_equal hover_colors["accent"], pointer_selection["border"]
    assert_equal "none", pointer_selection["outline"]
    assert_equal "solid", pointer_selection["linkOutline"]

    find(".index-picker__row.is-selected .index-picker__card-open").send_keys(:escape)
    assert_no_selector ".index-picker__row.is-selected"
  end

  test "registry category counts toggle live without moving the page or existing cards" do
    visit root_path(sort: "name")
    assert_no_selector ".index-console.is-filter-open"
    find(".index-search__filter-toggle").click
    assert_selector ".index-console.is-filter-open .index-picker__layer-head"
    assert_selector ".index-search__filter-toggle.is-active[aria-expanded='true']"
    page.execute_script <<~JS
      document.body.dataset.categoryNavigation = "live"
      document.querySelector(".index-picker__layer-head").scrollIntoView({ block: "center" })
      window.__filterCard = document.querySelector(".index-picker__card")
      window.__filterCardLeft = window.__filterCard.getBoundingClientRect().left
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if (new URL(url).searchParams.get("category") !== "appearance") {
          return window.__realFetch(url, options)
        }
        return new Promise((resolve, reject) => {
          const timer = window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 300)
          options.signal?.addEventListener("abort", () => {
            window.clearTimeout(timer)
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true })
        })
      }
    JS
    scroll_before = page.evaluate_script("window.scrollY")
    find("a.index-picker__category[data-category='appearance']").click
    sleep 0.08
    pending_motion = page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector(".index-picker")
        return {
          sameCard: document.querySelector(".index-picker__card") === window.__filterCard,
          leftDelta: document.querySelector(".index-picker__card").getBoundingClientRect().left - window.__filterCardLeft,
          animation: getComputedStyle(picker).animationName,
          transform: getComputedStyle(picker).transform
        }
      })()
    JS
    assert pending_motion["sameCard"]
    assert_in_delta 0, pending_motion["leftDelta"], 0.1
    assert_equal "none", pending_motion["animation"]
    assert_equal "none", pending_motion["transform"]

    assert_selector ".index-picker__row", count: 1
    assert_selector ".index-picker__row", text: "gamma"
    assert_equal({ "sort" => "name", "category" => "appearance" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_no_selector ".index-picker__filter-label, .index-picker__filter-glyph"
    assert_selector "a.index-picker__category.is-active[aria-label^='Clear appearance category filter,']", text: /appearance 1/i
    filter_insets = page.evaluate_script <<~JS
      (() => {
        const search = document.querySelector(".index-search").getBoundingClientRect()
        const searchEntry = document.querySelector(".index-search__entry").getBoundingClientRect()
        const filterToggle = document.querySelector(".index-search__filter-toggle").getBoundingClientRect()
        const layer = document.querySelector(".index-picker__layer-head").getBoundingClientRect()
        const filters = [...document.querySelectorAll("a.index-picker__category")]
        const first = filters[0].getBoundingClientRect()
        const last = filters.at(-1).getBoundingClientRect()
        return {
          searchLeft: searchEntry.left - search.left,
          searchRight: search.right - filterToggle.right,
          filterLeft: first.left - layer.left,
          filterRight: layer.right - last.right,
          activeMarker: getComputedStyle(document.querySelector("a.index-picker__category.is-active"), "::before").content
        }
      })()
    JS
    assert_in_delta filter_insets["searchLeft"], filter_insets["filterLeft"], 0.1
    assert_in_delta filter_insets["searchRight"], filter_insets["filterRight"], 0.1
    assert_equal "none", filter_insets["activeMarker"]
    Selenium::WebDriver::Wait.new(timeout: 2).until do
      page.evaluate_script("getComputedStyle(document.querySelector('.index-picker__category.is-active')).color") ==
        page.evaluate_script("getComputedStyle(document.querySelector('.index-picker__category.is-active strong')).color")
    end
    assert_equal "live", page.evaluate_script("document.body.dataset.categoryNavigation")
    assert_equal "appearance", page.evaluate_script("document.activeElement.dataset.category")
    assert_in_delta scroll_before, page.evaluate_script("window.scrollY"), 1
    assert_nil find(".index-picker", visible: :all)["data-level-transition"]

    scroll_before_clear = page.evaluate_script("window.scrollY")
    find("a.index-picker__category.is-active").click
    assert_selector ".index-picker__row", count: 3
    assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_no_selector "a.index-picker__category.is-active"
    assert_equal "live", page.evaluate_script("document.body.dataset.categoryNavigation")
    assert_equal "appearance", page.evaluate_script("document.activeElement.dataset.category")
    assert_in_delta scroll_before_clear, page.evaluate_script("window.scrollY"), 1
    assert_nil find(".index-picker", visible: :all)["data-level-transition"]
  end

  test "Search and filter controls share compact type, height, and shadows" do
    visit root_path(q: "clock", sort: "name")
    find(".index-search__filter-toggle").click

    metrics = page.evaluate_script <<~JS
      (() => {
        const controls = [
          document.querySelector(".index-search__result"),
          document.querySelector(".index-search__clear"),
          document.querySelector(".index-search__reset"),
          document.querySelector(".index-search__form kbd"),
          document.querySelector(".index-search__filter-toggle"),
          document.querySelector(".index-picker__filter-option")
        ]
        const labels = [
          document.querySelector(".index-search__result"),
          document.querySelector(".index-search__clear small"),
          document.querySelector(".index-search__reset"),
          document.querySelector(".index-search__form kbd"),
          document.querySelector(".index-search__filter-toggle"),
          document.querySelector(".index-picker__filter-option")
        ]
        return {
          heights: controls.map((control) => control.getBoundingClientRect().height),
          fonts: labels.map((label) => getComputedStyle(label).fontSize),
          shadows: controls.map((control) => getComputedStyle(control).boxShadow),
          filterHeight: document.querySelector(".index-picker__layer-head").getBoundingClientRect().height
        }
      })()
    JS

    assert_equal [ 28 ], metrics["heights"].uniq
    assert_equal [ "10px" ], metrics["fonts"].uniq
    assert_equal 1, metrics["shadows"].uniq.size
    refute_equal "none", metrics["shadows"].first
    assert_equal 38, metrics["filterHeight"]
  end

  test "filter options wrap before Security can be clipped on a narrowing desktop" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 1121, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click

    filter_geometry = lambda do
      page.evaluate_script <<~JS
        (() => {
          const layer = document.querySelector(".index-picker__layer-head").getBoundingClientRect()
          const scroller = document.querySelector("[data-index-picker-target='visibleCategories']")
          const options = [...scroller.querySelectorAll(".index-picker__filter-option")]
          const boxes = options.map((option) => option.getBoundingClientRect())
          const security = boxes.at(-1)
          return {
            rows: new Set(boxes.map((box) => Math.round(box.top))).size,
            securityInside: security.right <= layer.right && security.left >= layer.left,
            allInside: boxes.every((box) => box.left >= layer.left && box.right <= layer.right &&
              box.top >= layer.top && box.bottom <= layer.bottom),
            internalOverflow: scroller.scrollWidth - scroller.clientWidth,
            pageOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
          }
        })()
      JS
    end

    wide = filter_geometry.call
    assert_equal 1, wide["rows"]
    assert wide["securityInside"]
    assert wide["allInside"]
    assert_equal 0, wide["internalOverflow"]
    assert_equal 0, wide["pageOverflow"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 1120, height: 900, deviceScaleFactor: 1, mobile: false)
    wrapped = filter_geometry.call
    assert_equal 2, wrapped["rows"]
    assert wrapped["securityInside"]
    assert wrapped["allInside"]
    assert_equal 0, wrapped["internalOverflow"]
    assert_equal 0, wrapped["pageOverflow"]
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Development, Security, and Kids are direct browse filters" do
    publisher = Publisher.find_by!(name: "acme")
    development = Plugin.create!(publisher:, name: "forge", summary: "Developer tools",
      latest_version: "1.0.0", category: "developer-tools", tags: [ "security" ])
    development.versions.create!(version: "1.0.0", manifest: {}, sha256: "d" * 64,
      size_bytes: 1, state: :published, published_at: Time.current)
    kids = Plugin.create!(publisher:, name: "playroom", summary: "For children",
      latest_version: "1.0.0", category: "kids")
    kids.versions.create!(version: "1.0.0", manifest: {}, sha256: "e" * 64,
      size_bytes: 1, state: :published, published_at: Time.current)

    visit root_path(sort: "name")
    assert_selector ".index-search__filter-toggle[aria-expanded='false']"
    assert_no_selector ".index-console.is-filter-open"
    find(".index-search__filter-toggle").click
    find("body").send_keys(:escape)
    assert_no_selector ".index-console.is-filter-open"
    assert_selector ".index-search__filter-toggle[aria-expanded='false']:focus"
    find(".index-search__filter-toggle").click
    assert_selector "a.index-picker__category[data-category='developer-tools']", text: /development 1/i
    assert_no_selector "a.index-picker__category[data-category='developer-tools']", text: /developer-tools/i
    assert_selector "a.index-picker__tag[data-tag='security']", text: /security 1/i
    assert_selector "a.index-picker__category[data-category='kids']", text: /kids 1/i

    find("a.index-picker__category[data-category='kids']").click
    assert_selector ".index-picker__row", count: 1, text: "playroom"
    assert_equal({ "sort" => "name", "category" => "kids" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_selector "a.index-picker__category.is-active[data-category='kids']"

    find("body").send_keys(:escape)
    assert_no_selector ".index-console.is-filter-open"
    assert_selector ".index-search__filter-toggle[aria-expanded='false']:focus"
    assert_selector ".index-picker__row", count: 5
    assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_nil page.evaluate_script("document.querySelector('input[type=hidden][name=category]')?.value")

    find(".index-search__filter-toggle").click
    find("a.index-picker__tag[data-tag='security']").click
    assert_selector ".index-picker__row", count: 1, text: "forge"
    assert_equal({ "sort" => "name", "tag" => "security" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_selector "a.index-picker__tag.is-active[data-tag='security']"
    find(".index-search__filter-toggle").click
    assert_no_selector ".index-console.is-filter-open"
    assert_selector ".index-picker__row", count: 5
    assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
  end

  test "Escape from focused Search closes filters and preserves the query" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    search.set("ga")
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /gamma/i

    find(".index-search__filter-toggle").click
    find("a.index-picker__category[data-category='appearance']").click
    assert_selector ".index-console--has-context.is-filter-open"
    assert_selector "a.index-picker__category.is-active[data-category='appearance']"
    assert_equal({ "q" => "ga", "sort" => "name", "category" => "appearance" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))

    search.click
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /gamma/i
    search.send_keys(:escape)

    assert_no_selector ".index-console.is-filter-open"
    assert_no_selector ".index-search__suggestions"
    assert_selector ".index-search__filter-toggle[aria-expanded='false']:focus"
    assert_field "q", with: "ga"
    assert_nil page.evaluate_script("document.querySelector('input[type=hidden][name=category]')?.value")
    assert_equal({ "q" => "ga", "sort" => "name" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
  end

  test "a live response adds a category populated after the page was rendered" do
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    assert_no_selector "a.index-picker__category[data-category='bars']"

    publisher = Publisher.find_by!(name: "acme")
    plugin = Plugin.create!(publisher:, name: "fresh-bars", summary: "Fresh bar plugin",
      latest_version: "1.0.0", category: "bars")
    plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "f" * 64,
      size_bytes: 1, state: :published, published_at: Time.current)

    find("input[name='q']").set("fresh-bars")

    assert_selector ".index-picker__row", count: 1, text: "fresh-bars"
    assert_selector "a.index-picker__category[data-category='bars']", text: /bars 1/i
    assert_selector "a.index-picker__category[data-category='bars'][aria-label='Filter by bars category, 1 registry plugins']"
  end

  test "an active category remains clearable after live search reaches zero matches" do
    visit root_path(sort: "name", category: "appearance")
    assert_selector "a.index-picker__category.is-active[data-category='appearance']"

    find("input[name='q']").set("definitely-absent")
    assert_selector "[data-index-picker-target='live']", text: "No plugins match this search.", visible: :all
    assert_no_selector ".index-picker__row"
    assert_selector "a.index-picker__category.is-active[aria-label^='Clear appearance category filter,']", text: /appearance 1/i

    find("a.index-picker__category.is-active").click
    assert_no_selector "a.index-picker__category.is-active"
    assert_equal({ "q" => "definitely-absent", "sort" => "name" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_equal "appearance", page.evaluate_script("document.activeElement.dataset.category")
  end

  test "category links track pending search text before its request completes" do
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    find("input[name='q']").set("pending-query")

    href = URI(find("a.index-picker__category[data-category='appearance']")["href"])
    assert_equal({ "q" => "pending-query", "sort" => "name", "category" => "appearance" },
      Rack::Utils.parse_nested_query(href.query))
  end

  test "a failed live category toggle restores its previous filter state" do
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if (new URL(url).searchParams.get("category") === "appearance") {
          return Promise.resolve(new Response("{}", { status: 200, headers: { "Content-Type": "application/json" } }))
        }
        return window.__realFetch(url, options)
      }
    JS

    find("a.index-picker__category[data-category='appearance']").click
    assert_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
    assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_nil page.evaluate_script("document.querySelector('input[type=hidden][name=category]')?.value")
    assert_no_selector "a.index-picker__category.is-active"
    assert_no_selector ".index-console--has-context"
    assert_equal "all › results", page.evaluate_script("document.querySelector('[data-index-picker-target=breadcrumb]').textContent")
    assert_selector ".index-picker__row", count: 3
  end

  test "a failed FILTER reset restores combined selections and disclosure" do
    visit root_path(sort: "name", category: "appearance", tag: "clock")
    assert_selector ".index-console.is-filter-open"
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const parsed = new URL(url)
        if (!parsed.searchParams.has("category")) {
          return Promise.resolve(new Response("{}", {
            status: 200, headers: { "Content-Type": "application/json" }
          }))
        }
        return window.__realFetch(url, options)
      }
    JS

    find("body").send_keys(:escape)
    assert_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
    assert_selector ".index-console.is-filter-open"
    assert_selector ".index-search__filter-toggle.is-active[aria-expanded='true']:focus"
    assert_selector "a.index-picker__category.is-active[data-category='appearance']"
    assert_equal "all › category:appearance + tag:clock › results",
      page.evaluate_script("document.querySelector('[data-index-picker-target=breadcrumb]').textContent")
    assert_equal [ "appearance" ], all("input[type=hidden][name=category]", visible: :all).map(&:value).uniq
    assert_equal [ "clock" ], all("input[type=hidden][name=tag]", visible: :all).map(&:value).uniq
    assert_equal({ "sort" => "name", "category" => "appearance", "tag" => "clock" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
  end

  test "Turbo cache restores authoritative filters when navigation interrupts a reset" do
    visit root_path(sort: "name", category: "appearance")
    assert_selector ".index-console--has-context.is-filter-open"
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const parsed = new URL(url)
        if (!parsed.pathname.endsWith(".json") || parsed.searchParams.has("category")) {
          return window.__realFetch(url, options)
        }
        return new Promise((_resolve, reject) => {
          options.signal?.addEventListener("abort", () => {
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true })
        })
      }
    JS

    find(".index-search__filter-toggle").click
    assert_no_selector ".index-console.is-filter-open"
    assert_equal "appearance", Rack::Utils.parse_nested_query(URI(page.current_url).query)["category"]
    click_link "governance"
    assert_current_path governance_path

    page.go_back
    assert_current_path root_path(sort: "name", category: "appearance")
    assert_selector ".index-console--has-context.is-filter-open"
    assert_selector "a.index-picker__category.is-active[data-category='appearance']"
    assert_equal [ "appearance" ], all("input[type=hidden][name=category]", visible: :all).map(&:value).uniq
    assert_selector ".index-picker__row", count: 1, text: "gamma"
  end

  test "typing during a pending category request keeps the new filter and search focus" do
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const parsed = new URL(url)
        if (parsed.searchParams.get("category") !== "appearance" || parsed.searchParams.get("q")) {
          return window.__realFetch(url, options)
        }
        return new Promise((resolve, reject) => {
          const timer = window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 500)
          options.signal?.addEventListener("abort", () => {
            window.clearTimeout(timer)
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true })
        })
      }
    JS

    find("a.index-picker__category[data-category='appearance']").click
    search = find("input[name='q']")
    search.set("clock")

    page.execute_script <<~JS
      (() => {
        const element = document.querySelector("[data-index-picker-target='picker']")
        const markWhenLoaded = () => {
          const controller = window.Stimulus.getControllerForElementAndIdentifier(
            document.querySelector("[data-controller~='index-picker']"), "index-picker"
          )
          if (controller.loadedQuery === "clock" && !controller.request && !controller.searchTimer) {
            element.dataset.testLoadedQuery = "clock"
          } else {
            requestAnimationFrame(markWhenLoaded)
          }
        }
        markWhenLoaded()
      })()
    JS
    assert_selector "[data-index-picker-target='picker'][data-test-loaded-query='clock']", visible: :all
    assert_selector ".index-picker__row", count: 1
    assert_selector ".index-picker__row", text: "gamma"
    assert_equal({ "q" => "clock", "sort" => "name", "category" => "appearance" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_equal "appearance", find("input[type='hidden'][name='category']", visible: :all).value
    assert page.evaluate_script("document.activeElement === document.querySelector('input[name=q]')")
  end

  test "escape and outside clicks clear selection while browser commands remain global" do
    visit root_path(sort: "name")
    assert_no_selector ".index-picker__row.is-selected"

    find("body").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "alpha"

    find(".statusfoot__end").click
    assert_no_selector ".index-picker__row.is-selected"
    find("body").send_keys(:enter)
    assert_current_path root_path(sort: "name")
    find("body").send_keys(:arrow_right)
    find("body").send_keys(:enter)
    assert_current_path plugin_path("acme", "alpha")

    visit root_path(q: "clock", sort: "name")
    search = find("input[name='q']")
    search.send_keys(:escape)
    assert_current_path root_path(q: "clock", sort: "name")
    assert_field "q", with: "clock"
    assert_no_selector ".index-search__suggestions"
    search.send_keys(:escape)
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-picker__row.is-selected"

    visit root_path(q: "clock", sort: "name")
    find(".statusfoot__end").click
    assert_no_selector ".index-picker__row.is-selected"
    find("body").send_keys(:backspace)
    assert_current_path root_path(sort: "name")
  end

  test "space copies the selected install command and confirms it visibly" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__copiedCommand = null
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: async (text) => { window.__copiedCommand = text } }
      })
    JS

    assert_selector ".index-picker__keys strong", text: "PGUP / PGDN", exact_text: true
    find("body").send_keys(:arrow_right)
    find("body").send_keys(:space)
    assert_equal "omarchy plugin add acme/alpha", page.evaluate_script("window.__copiedCommand")
    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"
    notice_geometry = page.evaluate_script <<~JS
      (() => {
        const notice = document.querySelector(".index-picker__copy-status")
        const rect = notice.getBoundingClientRect()
        return { position: getComputedStyle(notice).position, top: rect.top,
          right: getComputedStyle(notice).right, bottom: getComputedStyle(notice).bottom }
      })()
    JS
    assert_equal "fixed", notice_geometry["position"]
    assert_equal "20px", notice_geometry["right"]
    assert_equal "20px", notice_geometry["bottom"]
    page.execute_script("window.scrollBy(0, 300)")
    assert_in_delta notice_geometry["top"], page.evaluate_script(
      "document.querySelector('.index-picker__copy-status').getBoundingClientRect().top"), 2.5

    page.execute_script <<~JS
      navigator.clipboard.writeText = async () => { throw new Error("denied") }
      document.execCommand = () => false
    JS
    find("body").send_keys(:space)
    assert_selector ".index-picker__copy-status.is-visible", text: "Command could not be copied"

    find("body").send_keys(:escape)
    page.execute_script("window.__copiedCommand = 'unchanged'")
    find("body").send_keys(:space)
    assert_equal "unchanged", page.evaluate_script("window.__copiedCommand")
  end

  test "mobile copy confirmation stays attached to the viewport while selection moves" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(sort: "name")
    page.execute_script <<~JS
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: async () => {} }
      })
    JS
    find("body").send_keys("j")
    page.execute_script("document.querySelector('.index-picker__row.is-selected').scrollIntoView({ block: 'center' })")

    find("body").send_keys(:space)

    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"
    assert_no_selector ".index-picker__row > .index-picker__copy-status"
    geometry = page.evaluate_script <<~JS
      (() => {
        const notice = document.querySelector(".index-picker__copy-status").getBoundingClientRect()
        const navigation = document.querySelector(".mobile-nav").getBoundingClientRect()
        return { position: getComputedStyle(document.querySelector(".index-picker__copy-status")).position,
          right: getComputedStyle(document.querySelector(".index-picker__copy-status")).right,
          bottom: getComputedStyle(document.querySelector(".index-picker__copy-status")).bottom,
          clearsNavigation: notice.bottom <= navigation.top }
      })()
    JS
    assert_equal "fixed", geometry["position"]
    assert_equal "20px", geometry["right"]
    assert_equal "82px", geometry["bottom"]
    assert geometry["clearsNavigation"]

    find("body").send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "beta"
    assert_no_selector ".index-picker__copy-status.is-visible"
    find("body").send_keys(:space)
    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"

    search = find("input[name='q']")
    search.set("audio")
    assert_selector ".index-picker__row", count: 1, text: "beta"
    assert_no_selector ".index-picker__copy-status.is-visible"
    search.send_keys(:escape) if search["aria-expanded"] == "true"
    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "beta"
    find(".index-picker__row.is-selected .index-picker__card-open").send_keys(:space)
    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a stale clipboard result cannot follow selection or overwrite a newer confirmation" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__copyOperations = []
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: (text) => new Promise((resolve, reject) => {
          window.__copyOperations.push({ text, resolve, reject })
        }) }
      })
    JS

    find("body").send_keys(:arrow_right)
    find("body").send_keys(:space)
    find("body").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "beta"
    find("body").send_keys(:space)
    assert_equal 2, page.evaluate_script("window.__copyOperations.length")

    page.execute_script("window.__copyOperations[1].resolve()")
    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"
    page.execute_script("window.__copyOperations[0].reject(new Error('late failure'))")
    sleep 0.1

    assert_selector ".index-picker__copy-status.is-visible", text: "Command copied"
    assert_no_selector ".index-picker__copy-status", text: "Command could not be copied"
    assert_equal "omarchy plugin add acme/alpha", page.evaluate_script("window.__copyOperations[0].text")
    assert_equal "omarchy plugin add acme/beta", page.evaluate_script("window.__copyOperations[1].text")
  end

  test "a card follows its real link on the first click" do
    visit root_path(sort: "name")

    find(".index-picker__row", text: "beta").find(".index-picker__card-open").click
    assert_current_path plugin_path("acme", "beta")
  end

  test "Backspace returns from plugin details to the preserved Browse state" do
    visit root_path(q: "audio", sort: "name")
    find(".index-picker__row", text: "beta").find(".index-picker__card-open").click
    assert_current_path plugin_path("acme", "beta")

    find(".theme-toggle").click
    assert_selector ".theme-picker", visible: true
    page.driver.browser.action.send_keys(:backspace).perform
    assert_current_path plugin_path("acme", "beta")
    page.driver.browser.action.send_keys(:escape).perform

    page.execute_script <<~JS
      const input = document.createElement("input")
      input.id = "detail-editable-test"
      input.value = "x"
      document.body.append(input)
      input.focus()
    JS
    find("#detail-editable-test").send_keys(:backspace)
    assert_current_path plugin_path("acme", "beta")
    assert_field "detail-editable-test", with: ""
    page.execute_script("document.querySelector('#detail-editable-test').remove()")

    find("body").send_keys(:backspace)
    assert_current_path root_path(q: "audio", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "beta"
    assert_equal "browse", page.evaluate_script("window.location.hash.slice(1)")

    page.go_back
    assert_current_path plugin_path("acme", "beta")
    find("body").send_keys(:backspace)
    assert_current_path root_path(q: "audio", sort: "name")

    page.execute_script("sessionStorage.removeItem('registry-browse-return')")
    page.driver.browser.navigate.to(plugin_url("acme", "beta"))
    find("body").send_keys(:backspace)
    assert_current_path root_path
    assert_equal "browse", page.evaluate_script("window.location.hash.slice(1)")
  end

  test "plugin names share their canonical link while the rest of the card opens details" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__sharedPluginUrl = null
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: async (value) => { window.__sharedPluginUrl = value } }
      })
    JS

    name = find(".index-picker__row", text: "beta").find(".index-picker__card-name")
    name.hover
    hover = page.evaluate_script <<~JS
      (() => ({
        name: getComputedStyle([...document.querySelectorAll(".index-picker__card-name")]
          .find((link) => link.textContent.trim() === "beta")).color,
        accent: getComputedStyle(document.querySelector(".fetch__row .k")).color
      }))()
    JS
    assert_equal hover["accent"], hover["name"]

    modified_click = page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector("[data-controller~='index-picker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(picker, "index-picker")
        let prevented = false
        controller.sharePlugin({ type: "click", button: 0, ctrlKey: true, metaKey: false, shiftKey: false,
          altKey: false, preventDefault: () => { prevented = true }, stopPropagation: () => {} })
        return !prevented
      })()
    JS
    assert modified_click
    assert_nil page.evaluate_script("window.__sharedPluginUrl")
    assert_current_path root_path(sort: "name")

    name.click
    assert_current_path root_path(sort: "name")
    assert_equal plugin_url("acme", "beta"), page.evaluate_script("window.__sharedPluginUrl")
    assert_selector ".index-picker__copy-status.is-visible", text: "Plugin link copied"

    page.execute_script("window.__sharedPluginUrl = null")
    find(".index-picker__row", text: "gamma").find(".index-picker__card-name").send_keys(:space)
    assert_equal plugin_url("acme", "gamma"), page.evaluate_script("window.__sharedPluginUrl")
    assert_current_path root_path(sort: "name")

    find(".index-picker__row", text: "beta").find(".index-picker__card-open").click
    assert_current_path plugin_path("acme", "beta")
  end

  test "keyboard focus completes the hero before exposing its copy control" do
    visit root_path

    focused = page.evaluate_script <<~JS
      (() => {
        const hero = document.querySelector(".hero--reveal")
        hero.classList.remove("is-complete")
        const ticker = window.Stimulus.getControllerForElementAndIdentifier(
          hero.querySelector("[data-controller~='ticker']"), "ticker"
        )
        ticker.halt()
        ticker.phase = "in"
        ticker.tick = 3
        ticker.visible = true
        ticker.paused = false
        ticker.syncRunning()
        const button = hero.querySelector(".promptline__copy .copy-button")
        button.focus()
        const buttonBox = button.getBoundingClientRect()
        return {
          complete: hero.classList.contains("is-complete"),
          focused: document.activeElement === button,
          promptOpacity: getComputedStyle(hero.querySelector(".promptline--live")).opacity,
          revealClip: getComputedStyle(hero.querySelector(".promptline__reveal")).clipPath,
          copyOpacity: getComputedStyle(hero.querySelector(".promptline__copy")).opacity,
          visible: buttonBox.width > 0 && buttonBox.height > 0,
          buttonLabel: button.getAttribute("aria-label"),
          tickerPaused: ticker.paused,
          tickerRunning: ticker.running
        }
      })()
    JS
    assert focused["complete"]
    assert focused["focused"]
    assert focused["visible"]
    assert_equal "1", focused["promptOpacity"]
    assert_equal "inset(0px)", focused["revealClip"]
    assert_equal "1", focused["copyOpacity"]
    assert_equal "Copy install command", focused["buttonLabel"]
    assert focused["tickerPaused"]
    refute focused["tickerRunning"]
  end

  test "hero install prompt pauses on hover, copies, and resumes after mouseleave" do
    visit root_path
    page.execute_script <<~JS
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector(".hero--reveal"), "hero-reveal"
      ).finish()
      Object.defineProperty(navigator, "clipboard", {
        configurable: true,
        value: { writeText: async (text) => { window.__heroInstallCopy = text } }
      })
      const element = document.querySelector("[data-controller~='ticker']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
      controller.halt()
      controller.phase = "in"
      controller.tick = 3
      controller.visible = true
      controller.paused = false
      controller.syncRunning()
    JS

    find(".promptline--live").hover
    paused = page.evaluate_script <<~JS
      (() => {
        const element = document.querySelector("[data-controller~='ticker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
        return { paused: controller.paused, running: controller.running, tick: controller.tick }
      })()
    JS
    assert paused["paused"]
    refute paused["running"]
    sleep 0.06
    assert_equal paused["tick"], page.evaluate_script(<<~JS)
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='ticker']"), "ticker"
      ).tick
    JS
    assert_text "$ omarchy plugin add publisher/name"
    find(".promptline__copy").find_button("Copy install command").click
    sleep 0.1
    feedback = page.evaluate_script <<~JS
      (() => {
        const button = document.querySelector(".promptline__copy .copy-button")
        return {
          copied: window.__heroInstallCopy,
          done: button.classList.contains("copy-button--done"),
          label: button.getAttribute("aria-label")
        }
      })()
    JS
    assert feedback["done"]
    assert_equal "Install command copied", feedback["label"]
    assert_equal "omarchy plugin add publisher/name", feedback["copied"]

    page.execute_script("document.activeElement.blur()")
    find(".hero__wm").hover
    page.execute_script <<~JS
      (() => {
        const element = document.querySelector("[data-controller~='ticker']")
        const markWhenRunning = () => {
          const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
          if (controller.running) element.dataset.testRunning = "true"
          else requestAnimationFrame(markWhenRunning)
        }
        markWhenRunning()
      })()
    JS
    assert_selector "[data-controller~='ticker'][data-test-running='true']", visible: :all
    assert_equal({ "paused" => false, "running" => true }, page.evaluate_script(<<~JS))
      (() => {
        const element = document.querySelector("[data-controller~='ticker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
        return { paused: controller.paused, running: controller.running }
      })()
    JS

    cached = page.evaluate_script <<~JS
      (() => {
        const element = document.querySelector("[data-controller~='ticker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
        controller.resume()
        const scheduled = controller.resumeFrame !== null
        document.dispatchEvent(new Event("turbo:before-cache"))
        return { scheduled, resumeCanceled: controller.resumeFrame === null, running: controller.running }
      })()
    JS
    assert_equal({ "scheduled" => true, "resumeCanceled" => true, "running" => false }, cached)
  end

  test "hero ticker keeps its continuous sequence without adding a motion control" do
    visit root_path
    looped = page.evaluate_script <<~JS
      (() => {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='ticker']"), "ticker"
        )
        controller.halt()
        controller.index = controller.messagesValue.length - 1
        controller.setChars(controller.messagesValue[controller.index])
        controller.reveal = controller.chars.map(() => 0)
        controller.phase = "out"
        controller.tick = 12
        controller.visible = true
        controller.paused = false
        controller.step()
        return {
          phase: controller.phase,
          running: controller.running,
          index: controller.index,
          messages: controller.messagesValue,
          text: controller.chars.join("")
        }
      })()
    JS
    assert_no_selector ".promptline__ticker-toggle", visible: :all
    assert_equal "in", looped["phase"]
    assert looped["running"]
    assert_equal 0, looped["index"]
    assert_includes looped["messages"], "We can fix everything!"
    assert_equal "omarchy plugin add publisher/name", looped["text"]
  end

  test "hero ticker and Pacman cross the mobile breakpoint without stale animation work" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 900, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path
    page.execute_script <<~JS
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector(".hero--reveal"), "hero-reveal"
      ).finish()
    JS
    assert page.evaluate_script <<~JS
      (() => {
        const ticker = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='ticker']"), "ticker"
        )
        const pacman = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='pacman']"), "pacman"
        )
        return !ticker.staticMode && (ticker.running || ticker.hold != null) &&
          !pacman.motionQuery.matches && pacman.frame != null
      })()
    JS

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 360, height: 900, deviceScaleFactor: 1, mobile: false)
    page.execute_script("window.dispatchEvent(new Event('resize'))")
    assert page.evaluate_script <<~JS
      (() => {
        const ticker = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='ticker']"), "ticker"
        )
        const pacman = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='pacman']"), "pacman"
        )
        return ticker.staticMode && !ticker.running && ticker.frame == null && ticker.hold == null &&
          pacman.motionQuery.matches && pacman.frame == null && pacman.replayTimer == null
      })()
    JS

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 900, height: 900, deviceScaleFactor: 1, mobile: false)
    page.execute_script("window.dispatchEvent(new Event('resize'))")
    assert page.evaluate_script <<~JS
      (() => {
        const ticker = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='ticker']"), "ticker"
        )
        const pacman = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='pacman']"), "pacman"
        )
        return !ticker.staticMode && (ticker.running || ticker.hold != null) && ticker.canvasTarget.width > 0 &&
          !pacman.motionQuery.matches && pacman.frame != null
      })()
    JS
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "hero lead line spans the live prompt while preserving its supporting copy" do
    visit root_path
    page.execute_script <<~JS
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector(".hero--reveal"), "hero-reveal"
      ).finish()
    JS

    assert_equal "Plugins for people who love computers.", page.evaluate_script(
      'document.querySelector(".hero__lede-title").textContent'
    ).squish
    assert_text "Hosted, scanned, and revocable — every version is immutable, checksummed, and one command away. Discovery belongs on a web page. This is the web page."
    alignment = page.evaluate_script <<~JS
      (() => {
        const title = document.querySelector(".hero__lede-title").getBoundingClientRect()
        const prompt = document.querySelector(".promptline--live").getBoundingClientRect()
        const body = getComputedStyle(document.querySelector(".hero__lede-body"))
        const heading = getComputedStyle(document.querySelector(".hero__lede-title"))
        return {
          left: Math.abs(title.left - prompt.left),
          right: Math.abs(title.right - prompt.right),
          hierarchy: parseFloat(heading.fontSize) > parseFloat(body.fontSize)
        }
      })()
    JS
    assert_operator alignment["left"], :<, 1
    assert_operator alignment["right"], :<, 1
    assert alignment["hierarchy"]
  end

  test "mobile visitors omit the hero command box and its animation work" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 360, height: 900, deviceScaleFactor: 1, mobile: true)
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: true, maxTouchPoints: 1)
    visit root_path
    page.execute_script <<~JS
      window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector(".hero--reveal"), "hero-reveal"
      ).finish()
    JS

    touch = page.evaluate_script <<~JS
      (() => {
        const controller = window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("[data-controller~='ticker']"), "ticker"
        )
        return {
          hoverless: matchMedia("(hover: none)").matches,
          coarse: matchMedia("(pointer: coarse)").matches,
          promptHidden: getComputedStyle(document.querySelector(".promptline--live")).display === "none",
          tickerStatic: controller.staticMode && !controller.running && controller.frame == null && controller.hold == null
        }
      })()
    JS
    assert touch["hoverless"]
    assert touch["coarse"]
    assert touch["promptHidden"]
    assert touch["tickerStatic"]
  ensure
    page.driver.browser.execute_cdp("Emulation.setTouchEmulationEnabled", enabled: false)
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "ticker paints numeric metrics with the theme ANSI color 02" do
    visit root_path

    paints = page.evaluate_script <<~JS
      (() => {
        const element = document.querySelector("[data-controller~='ticker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "ticker")
        controller.halt()
        controller.setChars("12 PLUGINS")
        const calls = []
        const fillRects = []
        const original = controller.ctx.fillText
        const originalFillRect = controller.ctx.fillRect
        controller.ctx.fillText = function(character) { calls.push([character, this.fillStyle]) }
        controller.ctx.fillRect = function(...rect) { fillRects.push(rect) }
        controller.paintStatic()
        const animatedCalls = []
        controller.reveal = controller.chars.map(() => 10)
        controller.tick = 0
        controller.phase = "in"
        controller.ctx.fillText = function(character) { animatedCalls.push([character, this.fillStyle]) }
        controller.paint()
        controller.ctx.fillText = original
        controller.ctx.fillRect = originalFillRect
        controller.ctx.fillStyle = controller.colors.ansi02
        const ansi02 = controller.ctx.fillStyle
        controller.ctx.fillStyle = controller.colors.text
        const text = controller.ctx.fillStyle
        return {
          calls, animatedCalls, fillRects, width: controller.cssWidth, height: controller.cssHeight,
          ansi02, text
        }
      })()
    JS

    assert paints["calls"].select { |character, _color| /\d/.match?(character) }
      .all? { |_character, color| color == paints["ansi02"] }
    assert paints["calls"].select { |character, _color| /[A-Z]/.match?(character) }
      .all? { |_character, color| color == paints["text"] }
    assert paints["animatedCalls"].first(2).all? { |_character, color| color == paints["ansi02"] }
    assert_equal 2, paints["fillRects"].size
    assert paints["fillRects"].all? { |x, y, width, height| x.zero? && y.zero? && width == paints["width"] && height == paints["height"] }
  end

  test "unused search keeps reset, shortcut, and FILTER at the right edge" do
    visit root_path(sort: "name")

    positions = page.evaluate_script <<~JS
      (() => {
        const entry = document.querySelector(".index-search__entry").getBoundingClientRect()
        const reset = document.querySelector(".index-search__reset").getBoundingClientRect()
        const shortcut = document.querySelector(".index-search__form kbd").getBoundingClientRect()
        const search = document.querySelector(".index-search").getBoundingClientRect()
        const filterToggle = document.querySelector(".index-search__filter-toggle").getBoundingClientRect()
        const filter = document.querySelector(".index-picker__layer-head")
        const firstCard = document.querySelector(".index-picker__card").getBoundingClientRect()
        return {
          countHidden: document.querySelector(".index-search__result").hidden,
          clearHidden: document.querySelector(".index-search__clear").hidden,
          controlsRight: entry.right < reset.left && reset.right < shortcut.left && shortcut.right < filterToggle.left,
          filterCollapsed: getComputedStyle(filter).display === "none",
          searchCardGap: firstCard.top - search.bottom
        }
      })()
    JS

    assert positions["countHidden"]
    assert positions["clearHidden"]
    assert positions["controlsRight"]
    assert positions["filterCollapsed"]
    assert_in_delta 7, positions["searchCardGap"], 0.1
    compact_counts = page.evaluate_script <<~JS
      (() => {
        const element = document.querySelector("[data-controller~='index-picker']")
        const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "index-picker")
        return [999, 1000, 1234, 9999, 12345, 999999, 1234567].map((number) => controller.compactNumber(number))
      })()
    JS
    assert_equal %w[999 1k 1.23k 10k 12.3k 1M 1.23M], compact_counts
  end

  test "search cursor, result box, and frameless Browse stay legible" do
    visit root_path(q: "clock", sort: "name")
    find(".index-search__filter-toggle").click

    find(".index-search__entry").click
    assert_equal "q", page.evaluate_script("document.activeElement.name")
    sleep 0.4

    metrics = page.evaluate_script <<~JS
      (() => {
        const inputElement = document.querySelector("input[name='q']")
        const input = inputElement.getBoundingClientRect()
        const cursorElement = document.querySelector(".index-search__cursor")
        const cursor = cursorElement.getBoundingClientRect()
        const clear = document.querySelector(".index-search__clear")
        const clearRect = clear.getBoundingClientRect()
        const reset = document.querySelector(".index-search__reset")
        const resultElement = document.querySelector(".index-search__result")
        const result = resultElement.getBoundingClientRect()
        const searchElement = document.querySelector(".index-search")
        const search = searchElement.getBoundingClientRect()
        const searchForm = document.querySelector(".index-search__form").getBoundingClientRect()
        const browseTitle = document.querySelector(".index-browse__title").getBoundingClientRect()
        const recentTitle = document.querySelector(".recent-band .boxtitle").getBoundingClientRect()
        const recentRow = document.querySelector(".recent-row").getBoundingClientRect()
        const sort = getComputedStyle(document.querySelector(".index-browse__sort a"))
        const command = getComputedStyle(document.querySelector(".index-browse__sort summary > span"))
        const recentCommand = getComputedStyle(document.querySelector(".recent-band__more"))
        const rule = document.querySelector(".index-browse__rule").getBoundingClientRect()
        const frontElement = document.querySelector(".index-picker")
        const front = frontElement.getBoundingClientRect()
        const filterElement = document.querySelector(".index-picker__layer-head")
        const gridElement = document.querySelector(".index-picker__grid")
        const firstCardElement = document.querySelector(".index-picker__card:nth-child(1)")
        const thirdCardElement = document.querySelector(".index-picker__card:nth-child(3)")
        const lastCardElement = document.querySelector(".index-picker__card:nth-child(9)")
        const statusElement = document.querySelector(".index-picker__status")
        const statusLeft = document.querySelector(".index-picker__status-left").getBoundingClientRect()
        const statusKeys = document.querySelector(".index-picker__keys").getBoundingClientRect()
        const navText = [...document.querySelectorAll(".index-picker__status-item > b, .index-picker__home")]
        const keyText = [...document.querySelectorAll(".index-picker__key-hint > strong")]
        const categoryLinks = [...document.querySelectorAll("a.index-picker__category")]
        const categoryColors = new Set(categoryLinks.map((item) => getComputedStyle(item).color))
        const resetStyle = getComputedStyle(document.querySelector(".index-search__reset"))
        const categoryCountColors = new Set(categoryLinks.map((item) => getComputedStyle(item.querySelector("strong")).color))
        const panelBackgrounds = new Set([
          ".promptline", ".recent-card", ".index-search", ".index-picker__layer-head", ".index-picker__card", ".index-picker__status"
        ].map((selector) => getComputedStyle(document.querySelector(selector)).backgroundColor))
        const fetchHead = document.querySelector(".fetch__head").getBoundingClientRect()
        const fetchNumber = getComputedStyle(document.querySelector(".fetch__head strong"))
        const fetchLabel = getComputedStyle(document.querySelector(".fetch__head span"))
        const fetchRule = document.querySelector(".fetch__rule").getBoundingClientRect()
        const recentBottom = Math.max(...[...document.querySelectorAll(".recent-card")]
          .map((card) => card.getBoundingClientRect().bottom))
        const cardMetadata = [".index-picker__card-publisher", ".index-picker__card-signals", ".index-picker__card-artifact"]
          .map((selector) => document.querySelector(selector))
        const newMarker = document.querySelector(".index-picker__card-signals mark")
        const singleCaret = getComputedStyle(cursorElement).visibility === "hidden" && getComputedStyle(inputElement).caretColor !== "transparent"
        inputElement.blur()
        const cursorAnimation = getComputedStyle(cursorElement).animationName
        inputElement.focus()
        const firstCard = firstCardElement.getBoundingClientRect()
        const thirdCard = thirdCardElement.getBoundingClientRect()
        const lastCard = lastCardElement.getBoundingClientRect()
        const status = statusElement.getBoundingClientRect()
        return {
          cursorBeforeInput: cursor.right <= input.left && input.left - cursor.right <= 8,
          cursorAnimation,
          singleCaret,
          clearBoxed: getComputedStyle(clear).borderStyle !== "none" && clearRect.width >= 28 && clearRect.height >= 28,
          clearBeforeReset: clearRect.right <= reset.getBoundingClientRect().left && reset.getBoundingClientRect().left - clearRect.right <= 13,
          escMatchesReset: getComputedStyle(clear.querySelector("small")).fontSize === getComputedStyle(reset).fontSize &&
            getComputedStyle(clear.querySelector("small")).fontWeight === getComputedStyle(reset).fontWeight,
          activeSearchLevel: searchElement.classList.contains("is-active") &&
            getComputedStyle(document.querySelector(".index-search__examples")).display !== "none",
          examples: document.querySelectorAll(".index-search__examples a").length,
          noExplainBlock: !document.querySelector(".index-query-plan"),
          resultBoxed: getComputedStyle(resultElement).borderStyle !== "none" &&
            result.width >= 28 && result.height >= 28,
          resultBeforeClear: result.right <= clearRect.left && clearRect.left - result.right <= 13,
          resultAccented: getComputedStyle(resultElement).borderTopColor ===
            getComputedStyle(resultElement).color,
          sortSize: parseFloat(sort.fontSize),
          sortWeight: parseInt(sort.fontWeight, 10),
          commandSize: parseFloat(command.fontSize),
          recentCommandSize: parseFloat(recentCommand.fontSize),
          commandWeight: parseInt(command.fontWeight, 10),
          recentCommandWeight: parseInt(recentCommand.fontWeight, 10),
          browseRule: rule.width >= 16 && rule.height === 1,
          matchingBrowseCountSize: getComputedStyle(document.querySelector(".index-browse__title h2")).fontSize ===
            getComputedStyle(document.querySelector(".index-browse__range")).fontSize,
          baseRemoved: !document.querySelector(".index-browse-layer"),
          frontAligned: Math.abs(front.left - search.left) < 1 && Math.abs(front.right - search.right) < 1,
          browseFrameless: parseFloat(getComputedStyle(frontElement).borderTopWidth) === 0,
          filterBoxed: getComputedStyle(filterElement).borderStyle !== "none" &&
            !filterElement.querySelector(".index-picker__filter-label, .index-picker__filter-glyph"),
          footerBoxed: getComputedStyle(statusElement).borderStyle !== "none" &&
            statusElement.textContent.trim().toLowerCase().startsWith("nav/"),
          balancedFooterInsets: Math.abs((statusLeft.left - status.left) - (status.right - statusKeys.right)) < 1,
          matchingFooterTypography: new Set([...navText, ...keyText].map((item) =>
            `${getComputedStyle(item).fontSize}/${getComputedStyle(item).fontWeight}`)).size === 1 &&
            getComputedStyle(document.querySelector(".index-picker__status-left")).columnGap ===
              getComputedStyle(document.querySelector(".index-picker__keys")).columnGap,
          matchingSectionHeadingGaps: Math.abs((search.top - browseTitle.bottom) - (recentRow.top - recentTitle.bottom)) < 0.5 &&
            Math.abs(search.top - browseTitle.bottom - 18) < 0.5,
          filterCardGap: firstCard.top - filterElement.getBoundingClientRect().bottom,
          filterGridGap: gridElement.getBoundingClientRect().top - filterElement.getBoundingClientRect().bottom,
          cardGridGap: firstCard.top - gridElement.getBoundingClientRect().top,
          cardFooterGap: status.top - lastCard.bottom,
          compactSearch: searchForm.height > filterElement.getBoundingClientRect().height &&
            searchForm.height <= filterElement.getBoundingClientRect().height + 20,
          gridUnpadded: parseFloat(getComputedStyle(gridElement).paddingLeft) === 0 &&
            parseFloat(getComputedStyle(gridElement).paddingRight) === 0,
          cardsFillBrowse: Math.abs(firstCard.left - front.left) < 1 && Math.abs(thirdCard.right - front.right) < 1,
          tallerCards: firstCard.height >= 250,
          doubledCardFooter: document.querySelector(".index-picker__card-foot").getBoundingClientRect().height >= 62 &&
            document.querySelector(".index-picker__card-foot").querySelectorAll(":scope > span").length === 2,
          noCardHeader: !document.querySelector(".index-picker__card-head"),
          readableCardMetadata: new Set(cardMetadata.map((item) => getComputedStyle(item).fontSize)).size === 1 &&
            new Set(cardMetadata.map((item) => getComputedStyle(item).color)).size === 1,
          publisherWithoutSlash: !document.querySelector(".index-picker__card-publisher").textContent.endsWith("/"),
          cardSignalIcons: document.querySelector(".index-picker__upvote-glyph")?.tagName === "svg" &&
            document.querySelector(".index-picker__view-glyph")?.tagName === "svg" &&
            Boolean(document.querySelector(".index-picker__view-glyph circle")),
          newMarkerUnboxed: parseFloat(getComputedStyle(newMarker).borderTopWidth) === 0 &&
            getComputedStyle(newMarker).backgroundColor === "rgba(0, 0, 0, 0)",
          noShadow: getComputedStyle(frontElement).boxShadow === "none",
          neutralCategories: categoryColors.size === 1,
          accentedCategoryCounts: categoryCountColors.size === 1 &&
            [...categoryCountColors][0] !== [...categoryColors][0],
          boxedCategoryFilters: categoryLinks.every((item) => {
            const style = getComputedStyle(item)
            return style.display === resetStyle.display && style.minHeight === resetStyle.minHeight &&
              style.borderTopStyle === resetStyle.borderTopStyle && style.paddingLeft === resetStyle.paddingLeft &&
              style.paddingRight === resetStyle.paddingRight && style.lineHeight === resetStyle.lineHeight
          }),
          categorySeparatorsRemoved: categoryLinks.every((item) =>
            getComputedStyle(item, "::after").content === "none"),
          uniformPanelBackgrounds: panelBackgrounds.size === 1,
          pluginMetricEyecatcher: parseFloat(fetchNumber.fontSize) > parseFloat(fetchLabel.fontSize) * 2.5 &&
            Math.abs(fetchRule.width - fetchHead.width) < 1 && fetchRule.top > fetchHead.bottom,
          recentClearsSearch: search.top - recentBottom >= 20
        }
      })()
    JS

    assert metrics["cursorBeforeInput"]
    assert_equal "cursor-blink", metrics["cursorAnimation"]
    assert metrics["singleCaret"]
    assert metrics["clearBoxed"]
    assert metrics["clearBeforeReset"]
    assert metrics["escMatchesReset"]
    assert metrics["activeSearchLevel"]
    assert_equal 8, metrics["examples"]
    assert metrics["noExplainBlock"]
    assert metrics["resultBoxed"]
    assert metrics["resultBeforeClear"]
    assert metrics["resultAccented"]
    assert_equal 10, metrics["sortSize"]
    assert_operator metrics["sortWeight"], :>=, 700
    assert_in_delta metrics["recentCommandSize"], metrics["commandSize"], 0.1
    assert_equal metrics["recentCommandWeight"], metrics["commandWeight"]
    assert metrics["browseRule"]
    assert metrics["matchingBrowseCountSize"]
    assert metrics["baseRemoved"]
    assert metrics["frontAligned"]
    assert metrics["browseFrameless"]
    assert metrics["filterBoxed"]
    assert metrics["footerBoxed"]
    assert metrics["balancedFooterInsets"]
    assert metrics["matchingFooterTypography"]
    assert metrics["matchingSectionHeadingGaps"]
    assert_in_delta 7, metrics["filterGridGap"], 1.1, metrics.inspect
    assert_in_delta 0, metrics["cardGridGap"], 0.1, metrics.inspect
    assert_in_delta 7, metrics["filterCardGap"], 1.1, metrics.inspect
    assert_in_delta 7, metrics["cardFooterGap"], 1.1
    assert metrics["compactSearch"]
    assert metrics["gridUnpadded"]
    assert metrics["cardsFillBrowse"]
    assert metrics["tallerCards"]
    assert metrics["doubledCardFooter"]
    assert metrics["noCardHeader"]
    assert metrics["readableCardMetadata"]
    assert metrics["publisherWithoutSlash"]
    assert metrics["cardSignalIcons"]
    assert metrics["newMarkerUnboxed"]
    assert metrics["noShadow"]
    assert metrics["neutralCategories"]
    assert metrics["accentedCategoryCounts"]
    assert metrics["boxedCategoryFilters"]
    assert metrics["categorySeparatorsRemoved"]
    assert metrics["uniformPanelBackgrounds"]
    assert metrics["pluginMetricEyecatcher"]
    assert metrics["recentClearsSearch"]

    find("input[name='q']").send_keys(:tab)
    assert_includes page.evaluate_script("document.activeElement.className"), "index-search__clear"
    page.driver.browser.switch_to.active_element.send_keys(:enter)
    assert_current_path root_path(sort: "name")
    assert_field "q", with: ""
    assert_selector ".index-search__clear[hidden]", visible: :all
    assert_no_selector ".index-query-plan"
    assert_no_selector ".index-search__examples"
    assert_selector ".recent-band:not([hidden])"
  end

  test "Fish completion is additive while the server remains the search authority" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    assert_equal "combobox", search["role"]
    assert_equal "both", search["aria-autocomplete"]
    assert_equal "false", search["aria-expanded"]
    assert_no_selector ".index-search__suggestions"

    search.set("al")
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /alpha.*plugin.*@acme/im
    assert_equal "true", search["aria-expanded"]
    assert_selector ".index-search__fish:not([hidden])", text: "pha"
    fish_colors = page.evaluate_script <<~JS
      (() => ({
        entered: getComputedStyle(document.querySelector("input[name='q']")).color,
        suggested: getComputedStyle(document.querySelector(".index-search__fish b")).color
      }))()
    JS
    assert_not_equal fish_colors["entered"], fish_colors["suggested"]
    assert_selector ".index-search__result[data-state='live']", text: "1"
    assert_selector ".index-browse__range", text: /1–1.*\/.*1/m
    assert_no_selector ".index-query-plan"

    modifier_preserved = page.evaluate_script <<~JS
      (() => {
        const input = document.querySelector("input[name='q']")
        const event = new KeyboardEvent("keydown", { key: "ArrowRight", ctrlKey: true, bubbles: true, cancelable: true })
        input.dispatchEvent(event)
        return !event.defaultPrevented && input.value === "al"
      })()
    JS
    assert modifier_preserved

    assert_no_selector ".index-picker__row.is-selected"
    search.click
    search.send_keys(:arrow_down)
    assert_equal "search-suggestion-0", search["aria-activedescendant"]
    assert_no_selector ".index-picker__row.is-selected"
    last_suggestion_id = all(".index-search__suggestions [role='option']").last[:id]
    search.send_keys(:arrow_up)
    assert_equal last_suggestion_id, search["aria-activedescendant"]
    assert_no_selector ".index-picker__row.is-selected"
    search.send_keys(:arrow_down)
    assert_equal "search-suggestion-0", search["aria-activedescendant"]

    search.send_keys(:arrow_right)
    assert_field "q", with: "alpha"
    assert_current_path root_path(q: "alpha", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "alpha"
    assert_no_selector ".index-picker__row", text: "beta"
    assert_no_selector ".index-search__suggestions"
    modified_enter_preserved = page.evaluate_script <<~JS
      (() => {
        const input = document.querySelector("input[name='q']")
        const before = location.href
        const event = new KeyboardEvent("keydown", { key: "Enter", ctrlKey: true, bubbles: true, cancelable: true })
        input.dispatchEvent(event)
        return !event.defaultPrevented && location.href === before
      })()
    JS
    assert modified_enter_preserved

    search.set("be")
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /beta.*plugin.*@acme/im
    search.send_keys(:arrow_down)
    assert_equal "search-suggestion-0", search["aria-activedescendant"]
    search.send_keys(:enter)
    assert_field "q", with: "beta"
    assert_current_path root_path(q: "beta", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "beta"
    assert_no_selector ".index-search__suggestions"

    search.send_keys(:enter)
    assert_current_path root_path(q: "beta", sort: "name")
    assert_field "q", with: "beta"
    assert_selector "[data-index-picker-target='live']", text: "Showing 1 plugin for “beta”.", visible: :all
    assert_operator page.evaluate_script(
      'Math.abs(document.querySelector("#browse").getBoundingClientRect().top)'
    ), :<, 2

    search = find("input[name='q']")
    search.set("ac")
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /@acme.*author.*3 plugins/im
    search.send_keys(:arrow_down)
    search.send_keys(:enter)
    assert_field "q", with: "@acme"
    assert_current_path root_path(q: "@acme", sort: "name")
    assert_selector ".index-picker__row", count: 3
    assert_selector ".index-picker__row", text: "alpha"
    assert_selector ".index-picker__row", text: "beta"
    assert_selector ".index-picker__row", text: "gamma"
    assert_no_selector ".index-search__suggestions"

    search.set("ga")
    assert_selector ".index-search__suggestions:not([hidden]) [role='option']", text: /gamma.*plugin.*@acme/im
    find(".index-search__suggestions [role='option']", text: /gamma/i).click
    assert_field "q", with: "gamma"
    assert_current_path root_path(q: "gamma", sort: "name")
    assert_no_selector ".index-search__suggestions"

    # Escape closes Fish first; with the list closed, ArrowDown keeps the
    # established Browse navigation.
    search.set("gam")
    assert_selector ".index-search__suggestions:not([hidden])"
    search.send_keys(:escape)
    assert_field "q", with: "gam"
    assert_no_selector ".index-search__suggestions"
    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "gamma"
    assert_field "q", with: "gam"
  end

  test "Enter accepts every Fish criterion and a second Enter explicitly presents its Browse results" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    criteria = [
      [ "al", "plugin", "alpha", 1 ],
      [ "@ac", "author", "@acme", 3 ],
      [ "kind:bar", "kind", "kind:bar-widget", 1 ],
      [ "tag:cl", "tag", "tag:clock", 1 ],
      [ "category:wid", "category", "category:widgets", 1 ]
    ]

    criteria.each do |draft, type, completion, count|
      search.set(draft)
      assert_selector ".index-search__suggestions:not([hidden]) [data-suggestion-type='#{type}']"
      search.send_keys(:enter)
      assert_field "q", with: completion
      assert_current_path root_path(q: completion, sort: "name")
      assert_selector ".index-picker__row", count: count

      search.send_keys(:enter)
      assert_selector "[data-index-picker-target='live']",
        text: "Showing #{count} #{count == 1 ? 'plugin' : 'plugins'} for “#{completion}”.", visible: :all
      assert_operator page.evaluate_script(
        'Math.abs(document.querySelector("#browse").getBoundingClientRect().top)'
      ), :<, 2
      search = find("input[name='q']")
    end

    search.set("text:clock")
    assert_no_selector ".index-search__suggestions"
    search.send_keys(:enter)
    assert_current_path root_path(q: "text:clock", sort: "name")
    assert_selector ".index-picker__row", count: 2
    assert_selector "[data-index-picker-target='live']", text: "Showing 2 plugins for “text:clock”.", visible: :all
  end

  test "server and live Browse cards format artifact sizes identically" do
    Plugin.find_by!(name: "alpha").versions.published.first.update!(size_bytes: 12_345)
    visit root_path(sort: "name")

    initial = find(".index-picker__row", text: "alpha").find(".index-picker__card-artifact").text.squish
    assert_includes initial, "12.1 KB"

    find("input[name='q']").set("alpha")
    assert_current_path root_path(q: "alpha", sort: "name")
    assert_selector ".index-picker__row", count: 1
    dynamic = find(".index-picker__row", text: "alpha").find(".index-picker__card-artifact").text.squish
    assert_equal initial, dynamic
  end

  test "live search updates cards, query plan, and keyboard selection" do
    visit root_path(sort: "name")
    assert_no_selector ".index-search__examples"

    search = find("input[name='q']")
    search.set("clock")
    assert_selector ".index-search__examples"
    assert_selector ".index-picker__row", count: 2
    assert_current_path root_path(q: "clock", sort: "name")
    assert_selector ".index-picker__row", text: "alpha"
    assert_selector ".index-picker__row", text: "gamma"
    assert_no_selector ".index-picker__row", text: "beta"
    assert_selector ".index-picker__row[data-name='alpha'] .index-picker__card-signals .visually-hidden",
      text: "New plugin, 30 downloads, 0 upvotes, 0 views", visible: :all
    accessibility_names = page.driver.browser.execute_cdp("Accessibility.getFullAXTree").fetch("nodes")
      .filter_map { |node| node.dig("name", "value") }
    assert accessibility_names.any? { |name| name.include?("30 downloads, 0 upvotes, 0 views") }
    assert_selector ".index-search__result[data-state='live']", text: "2"
    assert_selector ".index-browse__range", text: /1–2.*\/.*2/m
    assert_selector ".index-picker__card", count: HomeController::PER_PAGE
    assert_selector ".recent-band:not([hidden])"
    assert_nil search["aria-activedescendant"]

    search.send_keys(:escape)
    assert_field "q", with: "clock"
    assert_no_selector ".index-search__suggestions"
    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    find("body").send_keys(:enter)
    assert_current_path plugin_path("acme", "alpha")

    page.go_back
    assert_current_path root_path(q: "clock", sort: "name")
    assert_field "q", with: "clock"
    assert_selector ".index-picker__row", count: 2
    assert_selector ".recent-band:not([hidden])"

    find("input[name='q']").set("")
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 3
    assert_selector ".recent-band:not([hidden])"
  end

  test "sort links preserve a live query" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    search.set("clock")
    assert_selector ".index-picker__row", count: 2
    search.send_keys(:escape)
    assert_no_selector ".index-search__suggestions"

    find(".index-browse__sort summary").click
    assert_selector ".index-browse__sort.is-open .index-browse__sort-options"
    find(".index-browse__sort a", text: "DOWNLOADS", exact_text: true).click
    assert_current_path root_path(q: "clock")
    assert_field "q", with: "clock"
    assert_selector ".index-picker__row", count: 2
  end

  test "typing during a delayed sort keeps the new sort and Search focus" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__sortRequestAborted = false
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const parsed = new URL(url)
        if (parsed.searchParams.get("sort") !== "rating" || parsed.searchParams.get("q")) {
          return window.__realFetch(url, options)
        }
        return new Promise((resolve, reject) => {
          const timer = window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 600)
          options.signal?.addEventListener("abort", () => {
            window.clearTimeout(timer)
            window.__sortRequestAborted = true
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true })
        })
      }
    JS

    find(".index-browse__sort summary").click
    assert_selector ".index-browse__sort.is-open .index-browse__sort-options"
    find(".index-browse__sort a", text: "RATING", exact_text: true).click
    search = find("input[name='q']")
    search.set("audio")

    assert_current_path root_path(q: "audio", sort: "rating")
    assert_selector ".index-browse__sort a.is-active[aria-current='page']", visible: :all
    assert_selector ".index-picker__row", count: 1, text: "beta"
    assert_equal "q", page.evaluate_script("document.activeElement.name")
    assert page.evaluate_script("window.__sortRequestAborted")
  end

  test "a failed sort restores category links to the applied URL sort" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.fetch = (url) => {
        if (new URL(url).searchParams.get("sort") === "rating") {
          return Promise.resolve(new Response("{}", {
            status: 200, headers: { "Content-Type": "application/json" }
          }))
        }
        return Promise.reject(new Error("Unexpected request"))
      }
    JS

    find(".index-browse__sort summary").click
    assert_selector ".index-browse__sort.is-open .index-browse__sort-options"
    find(".index-browse__sort a", text: "RATING", exact_text: true).click

    assert_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
    assert_current_path root_path(sort: "name")
    assert_selector ".index-browse__sort a.is-active[aria-current='page']", visible: :all
    category_sort = page.evaluate_script <<~JS
      new URL(document.querySelector("a.index-picker__category").href).searchParams.get("sort")
    JS
    assert_equal "name", category_sort
  end

  test "footer key hints expose themed dismissible tooltips" do
    visit root_path(sort: "name")
    hint = find(".index-picker__key-hint[aria-describedby='browse-hint-enter']")
    page.execute_script("arguments[0].scrollIntoView({ block: 'center' })", hint)
    hint.hover

    tooltip = hint.find(".index-picker__key-tooltip", visible: :all)
    assert_equal "browse-hint-enter", tooltip[:id]
    assert_nil tooltip["aria-hidden"]
    assert_equal "Open the selected plugin", tooltip.text(:all).strip
    Selenium::WebDriver::Wait.new(timeout: 2).until { tooltip.visible? }
    assert_equal page.evaluate_script("getComputedStyle(document.querySelector('.index-picker__status')).backgroundColor"),
      page.evaluate_script("getComputedStyle(arguments[0]).backgroundColor", tooltip)
    assert_equal "solid", page.evaluate_script("getComputedStyle(arguments[0]).borderTopStyle", tooltip)

    hint.send_keys(:escape)
    assert_equal root_path(sort: "name"), URI(page.current_url).request_uri
    assert_equal "hidden", page.evaluate_script("getComputedStyle(arguments[0]).visibility", tooltip)

    page.execute_script("arguments[0].blur(); arguments[0].focus()", hint)
    assert_equal "visible", page.evaluate_script("getComputedStyle(arguments[0]).visibility", tooltip)
    hint.send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "alpha"

    find(".index-search__filter-toggle").click
    assert_selector ".index-console.is-filter-open"
    hint.send_keys(:escape)
    assert_no_selector ".index-console.is-filter-open"
    assert_selector ".index-search__filter-toggle[aria-expanded='false']:focus"
  end

  test "sort options slide open and dismiss from the arrow or outside" do
    visit root_path(sort: "name")
    summary = find(".index-browse__sort summary")
    assert_no_selector ".index-browse__sort[open]"

    summary.send_keys(:enter)
    assert_selector ".index-browse__sort.is-open[open] .index-browse__sort-options"
    Selenium::WebDriver::Wait.new(timeout: 2).until do
      page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__sort-options')).opacity") == "1"
    end
    transition = page.evaluate_script <<~JS
      (() => {
        const options = document.querySelector(".index-browse__sort-options")
        const style = getComputedStyle(options)
        return { opacity: style.opacity, transformX: new DOMMatrix(style.transform).m41, duration: style.transitionDuration }
      })()
    JS
    assert_equal "1", transition["opacity"]
    assert_in_delta 0, transition["transformX"], 0.1
    refute_equal "0s", transition["duration"]

    control_styles = page.evaluate_script <<~JS
      (() => {
        const properties = [
          "backgroundColor", "borderTopColor", "borderTopStyle", "boxShadow", "color",
          "fontFamily", "fontSize", "fontWeight", "letterSpacing", "lineHeight", "minHeight", "paddingLeft",
          "paddingRight", "textTransform"
        ]
        const styles = (element) => {
          const style = getComputedStyle(element)
          return Object.fromEntries(properties.map((property) => [property, style[property]]))
        }
        const filter = document.querySelector(".index-picker__filter-option")
        const normalFilter = styles(filter)
        filter.classList.add("is-active")
        filter.getAnimations().forEach((animation) => animation.finish())
        const activeFilter = styles(filter)
        filter.classList.remove("is-active")
        return {
          normalFilter,
          normalSort: styles([...document.querySelectorAll(".index-browse__sort a")]
            .find((link) => link.textContent.trim() === "downloads")),
          activeFilter,
          activeSort: styles(document.querySelector(".index-browse__sort a.is-active")),
          panelHeight: document.querySelector(".index-browse__sort-options").getBoundingClientRect().height
        }
      })()
    JS
    assert_equal control_styles["normalFilter"], control_styles["normalSort"]
    assert_equal control_styles["activeFilter"], control_styles["activeSort"]
    assert_in_delta 38, control_styles["panelHeight"], 0.5

    summary.send_keys(:space)
    assert_selector ".index-browse__sort.is-closing[open]"
    assert_no_selector ".index-browse__sort[open]"

    summary.send_keys(:enter)
    assert_selector ".index-browse__sort.is-open[open]"
    find(".index-search__entry").click
    assert_no_selector ".index-browse__sort[open]"
    assert_equal "q", page.evaluate_script("document.activeElement.name")

    page.execute_script <<~JS
      document.querySelector(".index-console").classList.remove("is-enhanced")
      document.querySelector(".index-browse__sort").open = true
    JS
    Selenium::WebDriver::Wait.new(timeout: 2).until do
      page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__sort-options')).opacity") == "1"
    end
    assert_equal "1", page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__sort-options')).opacity")
  end

  test "all sort links update Browse in place without jumping to the top" do
    visit root_path(sort: "name")
    page.execute_script("document.querySelector('.index-browse__title').scrollIntoView({ block: 'center' })")

    HomeController::SORTS.each_key do |sort|
      scroll_before = page.evaluate_script("window.scrollY")
      find(".index-browse__sort summary").click
      assert_selector ".index-browse__sort.is-open .index-browse__sort-options"
      find(".index-browse__sort a", text: sort.upcase, exact_text: true).click

      expected = sort == "downloads" ? {} : { "sort" => sort }
      assert_selector ".index-browse__sort a.is-active[aria-current='page']", visible: :all
      assert_equal sort, page.evaluate_script(
        "document.querySelector('.index-browse__sort a.is-active').textContent.trim()"
      )
      assert_current_path root_path(sort: (sort unless sort == "downloads"))
      assert_equal expected, Rack::Utils.parse_nested_query(URI(page.current_url).query)
      assert_no_selector ".index-browse__sort[open]"
      assert_in_delta scroll_before, page.evaluate_script("window.scrollY"), 1
    end
  end

  test "search enter stays in Browse after moving its card selection" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    search.send_keys(:enter)
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-picker__row.is-selected"

    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    search.send_keys(:enter)
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row.is-selected", text: "alpha"

    search.send_keys(:tab)
    find("body").send_keys(:enter)
    assert_current_path plugin_path("acme", "alpha")

    page.go_back
    find(".index-picker__row", text: "beta").find(".index-picker__card-open").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "gamma"
  end

  test "Search-owned Browse selection follows desktop arrow geometry" do
    publisher = Publisher.find_by!(name: "acme")
    6.times do |index|
      plugin = Plugin.create!(publisher:, name: "zed-#{index}", summary: "Arrow plugin",
        latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 4).to_s(16) * 64,
        size_bytes: 1, state: :published, published_at: Time.current)
    end

    visit root_path(sort: "name")
    search = find("input[name='q']")
    assert_no_selector ".index-picker__row.is-selected"
    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    search.send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "beta"
    search.send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "zed-1"
    search.send_keys(:arrow_left)
    assert_selector ".index-picker__row.is-selected", text: "zed-0"
    search.send_keys(:arrow_up)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    assert_equal "q", page.evaluate_script("document.activeElement.name")
    assert_current_path root_path(sort: "name")
  end

  test "visible keyboard commands work when the page body owns focus" do
    visit root_path(sort: "name")

    find("body").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    find("body").send_keys(:enter)
    assert_current_path plugin_path("acme", "alpha")

    visit root_path(q: "clock", sort: "name")
    find("body").send_keys(:backspace)
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-query-plan"
  end

  test "keyboard tile navigation brings Browse and the selected card into view" do
    visit root_path(sort: "name")
    page.execute_script("window.scrollTo(0, 0)")
    assert_no_selector ".index-picker__row.is-selected"
    assert_operator page.evaluate_script("document.querySelector('.index-picker__row').getBoundingClientRect().top"), :>,
      page.evaluate_script("window.innerHeight")

    find("body").send_keys(:arrow_right)
    assert_selector ".index-picker__row.is-selected", text: "alpha"
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script <<~JS
        (() => {
          const rect = document.querySelector(".index-picker__row.is-selected").getBoundingClientRect()
          return rect.top >= 12 && rect.bottom <= window.innerHeight - 12
        })()
      JS
    end
    assert_operator page.evaluate_script("window.scrollY"), :>, 0
    assert_operator page.evaluate_script("document.querySelector('.index-browse__title').getBoundingClientRect().bottom"), :>, 0
  end

  test "keyboard Browse reveal disables smooth scrolling with reduced motion" do
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia",
      features: [ { name: "prefers-reduced-motion", value: "reduce" } ])
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__browseScrollBehavior = null
      const nativeScrollIntoView = Element.prototype.scrollIntoView
      Element.prototype.scrollIntoView = function(options) {
        if (this.matches(".index-picker__row")) window.__browseScrollBehavior = options.behavior
        return nativeScrollIntoView.call(this, options)
      }
    JS

    find("body").send_keys("j")
    assert_equal "auto", page.evaluate_script("window.__browseScrollBehavior")
  ensure
    page.driver.browser.execute_cdp("Emulation.setEmulatedMedia", features: [])
  end

  test "keyboard navigation crosses the fixed nine-card window" do
    publisher = Publisher.find_by!(name: "acme")
    7.times do |index|
      plugin = Plugin.create!(publisher:, name: "extra-#{index}", summary: "Extra plugin", latest_version: "1.0.0",
        category: "other", downloads_count: 10 - index)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 3).to_s * 64,
        size_bytes: 1, state: :published, published_at: Time.current)
    end

    visit root_path(sort: "name")
    find("body").send_keys(:page_down)
    assert_selector ".index-picker__row", count: 1
    focus_state = page.evaluate_script <<~JS
      ({ active: document.activeElement.className,
        selected: document.querySelector(".index-picker__row.is-selected .index-picker__card-open")?.className,
        matches: document.activeElement.matches(".index-picker__row.is-selected .index-picker__card-open") })
    JS
    assert focus_state["matches"], focus_state.inspect
    assert_equal "2", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]
    assert_selector ".recent-band:not([hidden])"
    find("body").send_keys(:page_up)
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 9
    focus_state = page.evaluate_script <<~JS
      ({ active: document.activeElement.className,
        selected: document.querySelector(".index-picker__row.is-selected .index-picker__card-open")?.className,
        matches: document.activeElement.matches(".index-picker__row.is-selected .index-picker__card-open") })
    JS
    assert focus_state["matches"], focus_state.inspect

    10.times { find("body").send_keys("j") }
    assert_selector ".index-picker__row", count: 1
    assert_selector ".index-picker__card", count: HomeController::PER_PAGE
    assert_selector ".index-picker__row.is-selected", text: "gamma"
    assert_selector "[data-index-picker-target='resultRange']", text: /10–10 \/ 10/
    assert_equal "2", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]

    page.go_back
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 9
    page.go_forward
    assert_equal "2", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]
    assert_selector ".index-picker__row", count: 1
    find(".index-picker__row", text: "gamma").find(".index-picker__card-open").click
    assert_current_path plugin_path("acme", "gamma")

    page.go_back
    assert_equal "2", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]
    assert_selector ".index-picker__row", count: 1
    assert_selector "[data-index-picker-target='resultRange']", text: /10–10 \/ 10/

    find("body").send_keys("k")
    assert_selector ".index-picker__row", count: 9
    assert_selector ".index-picker__row.is-selected", text: "extra-6"
  end

  test "backspace returns an unfiltered result page to the previous page" do
    publisher = Publisher.find_by!(name: "acme")
    7.times do |index|
      plugin = Plugin.create!(publisher:, name: "back-#{index}", summary: "Backspace plugin",
        latest_version: "1.0.0", category: "other", downloads_count: index)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 3).to_s * 64,
        size_bytes: 1, state: :published, published_at: Time.current)
    end

    visit root_path(sort: "name", page: 2)
    assert_selector "[data-index-picker-target='resultRange']", text: /10–10 \/ 10/
    find("body").send_keys(:backspace)

    assert_current_path root_path(sort: "name")
    assert_selector "[data-index-picker-target='resultRange']", text: /1–9 \/ 10/
  end

  test "mouse wheel and held paging continue through result windows without changing level" do
    publisher = Publisher.find_by!(name: "acme")
    19.times do |index|
      plugin = Plugin.create!(publisher:, name: "wheel-#{index.to_s.rjust(2, '0')}", summary: "Wheel plugin",
        latest_version: "1.0.0", category: "other", downloads_count: index)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: ((index + 4) % 16).to_s(16) * 64,
        size_bytes: 1, state: :published, published_at: Time.current)
    end

    visit root_path(sort: "name")
    expected = all(".index-picker__row").first.text
    page.execute_script <<~JS
      document.querySelector(".index-picker").dispatchEvent(new WheelEvent("wheel", {
        deltaY: 100, bubbles: true, cancelable: true
      }))
    JS
    assert_equal expected, find(".index-picker__row.is-selected").text
    assert_current_path root_path(sort: "name")

    visit root_path(sort: "name")
    scroll_before = page.evaluate_script("window.scrollY")
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => new Promise((resolve, reject) => {
        window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 160)
      })
      const row = document.querySelectorAll(".index-picker__row")[7]
      row.focus({ preventScroll: true })
      const event = () => new KeyboardEvent("keydown", { key: "ArrowDown", bubbles: true, cancelable: true })
      row.dispatchEvent(event())
      row.dispatchEvent(event())
    JS
    assert_selector "[data-index-picker-target='resultRange']", text: /10–18 \/ 22/
    assert_equal "2", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]
    assert_equal "2", find("input[aria-label='Jump to result page']").value
    assert_equal 4, page.evaluate_script("[...document.querySelectorAll('.index-picker__row')].indexOf(document.querySelector('.index-picker__row.is-selected'))")
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script("document.querySelector('.index-picker__row.is-selected').getBoundingClientRect().bottom <= window.innerHeight - 12")
    end
    assert_operator page.evaluate_script("window.scrollY"), :>, scroll_before

    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => new Promise((resolve, reject) => {
        window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 160)
      })
      const event = () => new KeyboardEvent("keydown", { key: "PageDown", bubbles: true, cancelable: true })
      document.body.dispatchEvent(event())
      document.body.dispatchEvent(event())
    JS

    assert_selector "[data-index-picker-target='resultRange']", text: /19–22 \/ 22/
    assert_equal "3", find("input[aria-label='Jump to result page']").value
    assert_selector "[data-index-picker-target='pageTotal']", text: "3"
    assert_selector "[data-index-picker-target='visibleCategories']", text: /appearance 1.*kids 0.*system 1.*widgets 1.*other 19/im
    assert_no_selector ".index-picker.is-level-opening, .index-picker.is-level-returning"
    assert_selector ".recent-band:not([hidden])"
    assert_equal "3", Rack::Utils.parse_nested_query(URI(page.current_url).query)["page"]

    last_scroll = nil
    stable_checks = 0
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      current_scroll = page.evaluate_script("window.scrollY")
      stable_checks = current_scroll == last_scroll ? stable_checks + 1 : 0
      last_scroll = current_scroll
      stable_checks >= 2
    end
    scroll_before = page.evaluate_script("window.scrollY")
    find("body").send_keys(:page_down)
    assert_in_delta scroll_before, page.evaluate_script("window.scrollY"), 1

    page_input = find("input[aria-label='Jump to result page']")
    pagination_style = page.evaluate_script <<~JS
      (() => {
        const input = document.querySelector("input[aria-label='Jump to result page']")
        return {
          border: getComputedStyle(input).borderTopWidth,
          text: document.querySelector(".index-picker__pagination").textContent.replace(/\s+/g, " ").trim()
        }
      })()
    JS
    assert_equal "0px", pagination_style["border"]
    assert_no_match(/pgup|pgdn|\bpage\b/i, pagination_style["text"])
    arrow_colors = page.evaluate_script <<~JS
      (() => {
        const accent = getComputedStyle(document.querySelector(".index-picker__status-item > b")).color
        return {
          accent,
          arrows: [...document.querySelectorAll(".index-picker__pagination > a")]
            .map((arrow) => getComputedStyle(arrow).color)
        }
      })()
    JS
    assert arrow_colors["arrows"].all? { |color| color == arrow_colors["accent"] }
    page.execute_script("arguments[0].max = '999'", page_input)
    page_input.set("1")
    one_digit_width = page_input.evaluate_script("this.getBoundingClientRect().width")
    page_input.set("10")
    two_digit_width = page_input.evaluate_script("this.getBoundingClientRect().width")
    page_input.set("100")
    three_digit_width = page_input.evaluate_script("this.getBoundingClientRect().width")
    page_input.set("9" * 40)
    bounded_width = page_input.evaluate_script("this.getBoundingClientRect().width")
    assert_operator two_digit_width, :>, one_digit_width
    assert_operator three_digit_width, :>, two_digit_width
    assert_in_delta three_digit_width, bounded_width, 0.1
    page_input.set("1")
    page_input.send_keys(:enter)
    assert_current_path root_path(sort: "name")
    assert_equal "1", find("input[aria-label='Jump to result page']").value
  end

  test "popstate resizes a restored multi-digit page after a one-page search" do
    publisher = Publisher.find_by!(name: "acme")
    90.times do |index|
      plugin = Plugin.create!(publisher:, name: "history-#{index.to_s.rjust(2, '0')}", summary: "History plugin",
        latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index % 16).to_s(16) * 64,
        size_bytes: 1, state: :published, published_at: Time.current)
    end

    visit root_path(page: 10, sort: "name")
    assert_equal "10", find("input[aria-label='Jump to result page']").value
    search = find("input[name='q']")
    search.set("alpha")
    assert_current_path root_path(q: "alpha", sort: "name")
    one_page_width = find("input[aria-label='Jump to result page']").evaluate_script("this.getBoundingClientRect().width")

    page.go_back
    assert_current_path root_path(page: 10, sort: "name")
    assert_field "page", with: "10"
    page_input = find("input[aria-label='Jump to result page']")
    assert_equal "2", page_input.evaluate_script("this.style.getPropertyValue('--page-digits')")
    assert_operator page_input.evaluate_script("this.getBoundingClientRect().width"), :>, one_page_width
  end

  test "streamed JSON enforces the per-response byte boundary" do
    visit root_path(sort: "name")

    outcomes = page.evaluate_async_script <<~JS
      const done = arguments[0]
      const element = document.querySelector("[data-controller~='index-picker']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "index-picker")
      const responseAt = (bytes) => new Response("{}" + " ".repeat(bytes - 2), {
        headers: { "Content-Type": "application/json" }
      })
      Promise.all([524287, 524288, 524289].map((bytes) =>
        controller.boundedJson(responseAt(bytes)).then(() => true, () => false)
      )).then(done)
    JS

    assert_equal [ true, true, false ], outcomes
  end

  test "stalled search headers and response streams stop at the request deadline" do
    visit root_path(sort: "name")

    outcomes = page.evaluate_async_script <<~JS
      const done = arguments[0]
      const originalFetch = window.fetch
      const element = document.querySelector("[data-controller~='index-picker']")
      const controller = window.Stimulus.getControllerForElementAndIdentifier(element, "index-picker")
      controller.responseTimeoutMs = 35
      const run = async (fetchReplacement) => {
        window.fetch = fetchReplacement
        const started = performance.now()
        try {
          await controller.requestJson("/stalled.json", new AbortController())
          return { name: "resolved", elapsed: performance.now() - started }
        } catch (error) {
          return { name: error.name, elapsed: performance.now() - started }
        }
      }
      ;(async () => {
        let streamCancelled = false
        try {
          const headers = await run((_url, options) => new Promise((_resolve, reject) => {
            options.signal.addEventListener("abort", () => reject(options.signal.reason), { once: true })
          }))
          const stream = await run(() => Promise.resolve(new Response(new ReadableStream({
            cancel() { streamCancelled = true }
          }), { headers: { "Content-Type": "application/json" } })))
          return { headers, stream, streamCancelled }
        } finally {
          window.fetch = originalFetch
        }
      })().then(done, (error) => done({ error: String(error) }))
    JS

    assert_equal "TimeoutError", outcomes.dig("headers", "name")
    assert_equal "TimeoutError", outcomes.dig("stream", "name")
    assert_operator outcomes.dig("headers", "elapsed"), :<, 500
    assert_operator outcomes.dig("stream", "elapsed"), :<, 500
    assert outcomes["streamCancelled"]
  end

  test "rejected statuses and declared oversize responses cancel their streams" do
    visit root_path(sort: "name")

    outcome = page.evaluate_async_script <<~JS
      const done = arguments[0]
      const originalFetch = window.fetch
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("[data-controller~='index-picker']"), "index-picker")
      const cancelled = []
      const response = (label, init = {}) => new Response(new ReadableStream({
        cancel() { cancelled.push(label) }
      }), init)
      ;(async () => {
        try {
          window.fetch = () => Promise.resolve(response("status", { status: 503 }))
          await controller.requestJson("/unavailable.json", new AbortController()).catch(() => {})
          window.fetch = () => Promise.resolve(response("length", {
            headers: { "Content-Type": "application/json", "Content-Length": "524289" }
          }))
          await controller.requestJson("/oversized.json", new AbortController()).catch(() => {})
          return cancelled
        } finally {
          window.fetch = originalFetch
        }
      })().then(done, (error) => done({ error: String(error) }))
    JS

    assert_equal %w[status length], outcome
  end

  test "cleared selection survives an in-flight search and outside controls keep global commands" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => new Promise((resolve, reject) => {
        window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 360)
      })
    JS

    find("input[name='q']").set("clock")
    sleep 0.25
    previous = find("button.recent-band__step", text: "← previous")
    previous.click
    assert_no_selector ".index-picker__row.is-selected"
    assert_selector ".index-picker__row", count: 2
    assert_no_selector ".index-picker__row.is-selected"

    previous.send_keys(:backspace)
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-picker__row.is-selected"
  end

  test "a superseded slow response cannot overwrite a newer query" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if (!String(url).includes("q=clock")) return window.__realFetch(url, options)
        return new Promise((resolve, reject) => {
          const delayed = { ...options, signal: undefined }
          window.setTimeout(() => window.__realFetch(url, delayed).then(resolve, reject), 600)
        })
      }
    JS

    search = find("input[name='q']")
    search.set("clock")
    assert_selector ".index-search__result[data-state='loading']"
    loading_colors = page.evaluate_script <<~JS
      (() => {
        const result = document.querySelector(".index-search__result")
        const probe = document.createElement("span")
        probe.style.color = "var(--ansi-01-ink)"
        document.body.append(probe)
        const colors = {
          border: getComputedStyle(result).borderTopColor,
          color01: getComputedStyle(probe).color,
          line: getComputedStyle(document.documentElement).getPropertyValue("--line-strong").trim()
        }
        probe.remove()
        return colors
      })()
    JS
    assert_equal loading_colors["color01"], loading_colors["border"]
    refute_equal loading_colors["line"], loading_colors["border"]
    search.set("audio")
    assert_selector ".index-picker__row", count: 1, text: "beta"
    sleep 0.7
    assert_selector ".index-picker__row", count: 1, text: "beta"
    assert_current_path root_path(q: "audio", sort: "name")
  end

  test "live search accepts a published plugin without a summary" do
    publisher = Publisher.find_by!(name: "acme")
    plugin = Plugin.create!(publisher:, name: "nil-summary", summary: nil, latest_version: "1.0.0", kinds: [], tags: [])
    plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: "a" * 64,
      size_bytes: 1, state: :published, published_at: Time.current)

    visit root_path(sort: "name")
    find("input[name='q']").set("nil-summary")

    assert_current_path root_path(q: "nil-summary", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "nil-summary"
    assert_selector ".index-picker__card", count: HomeController::PER_PAGE
    assert_no_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
  end

  test "deep links canonicalize long and astral Unicode queries across history" do
    long_query = "x" * 170
    canonical_query = "x" * HomeController::MAX_QUERY_LENGTH
    astral_query = "🦊" * 100

    visit root_path(q: long_query, sort: "name")
    assert_current_path root_path(q: canonical_query, sort: "name")
    assert_field "q", with: canonical_query

    find("input[name='q']").set(astral_query)
    assert_current_path root_path(q: astral_query, sort: "name")
    assert_field "q", with: astral_query

    page.go_back
    assert_current_path root_path(q: canonical_query, sort: "name")
    assert_field "q", with: canonical_query
  end

  test "Unicode whitespace keeps server and history query semantics aligned" do
    spaced_query = "\u00a0beta\u00a0"

    visit root_path(q: spaced_query, sort: "name")
    assert_current_path root_path(q: spaced_query, sort: "name")
    assert_field "q", with: spaced_query
    assert_selector ".index-picker__row", count: 0

    find("input[name='q']").set("beta")
    assert_current_path root_path(q: "beta", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "beta"

    page.go_back
    assert_current_path root_path(q: spaced_query, sort: "name")
    assert_field "q", with: spaced_query
    assert_selector ".index-picker__row", count: 0
  end

  test "malformed Security facet counts fail closed without replacing Browse" do
    visit root_path(sort: "name")
    find(".index-search__filter-toggle").click
    original_names = all(".index-picker__row .index-picker__card-name").map(&:text)
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = async (url, options = {}) => {
        const query = new URL(url).searchParams.get("q") || ""
        if (!query.startsWith("tag-count-")) return window.__realFetch(url, options)
        const response = await window.__realFetch(url, options)
        const payload = await response.json()
        const mutation = query.slice("tag-count-".length)
        if (mutation === "missing") delete payload.taxonomy.tag_counts
        if (mutation === "null") payload.taxonomy.tag_counts = null
        if (mutation === "array") payload.taxonomy.tag_counts = []
        if (mutation === "extra") payload.taxonomy.tag_counts = { security: 0, other: 0 }
        if (mutation === "missing-key") payload.taxonomy.tag_counts = {}
        if (mutation === "string") payload.taxonomy.tag_counts = { security: "0" }
        if (mutation === "negative") payload.taxonomy.tag_counts = { security: -1 }
        if (mutation === "fractional") payload.taxonomy.tag_counts = { security: 0.5 }
        if (mutation === "unsafe") payload.taxonomy.tag_counts = { security: Number.MAX_SAFE_INTEGER + 1 }
        return new Response(JSON.stringify(payload), {
          status: 200, headers: { "Content-Type": "application/json" }
        })
      }
    JS

    %w[missing null array extra missing-key string negative fractional unsafe].each do |mutation|
      page.execute_script("document.querySelector('[data-index-picker-target=live]').textContent = ''")
      find("input[name='q']").set("tag-count-#{mutation}")
      assert_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
      assert_selector ".index-picker[data-search-stale='true']"
      assert_equal original_names, all(".index-picker__row .index-picker__card-name").map(&:text)
      assert_selector ".index-console.is-filter-open"
      assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
    end
  end

  test "malformed JSON and oversized bodies cannot replace the nine-card window" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const q = new URL(url).searchParams.get("q")
        const malformed = ["malformed", "bad-metadata", "underfilled", "wrong-context", "oversized-body", "unstreamed"]
        if (!malformed.includes(q)) return window.__realFetch(url, options)
        if (q === "unstreamed") {
          return Promise.resolve({ ok: true, headers: new Headers(), body: null,
            text: () => { throw new Error("unbounded fallback must not run") } })
        }
        if (q === "oversized-body") {
          return Promise.resolve(new Response("{}", { status: 200, headers: { "Content-Length": "524289" } }))
        }
        const count = q === "malformed" ? 10 : (q === "bad-metadata" ? 1 : 0)
        const total = q === "malformed" ? 10 : (q === "underfilled" ? 9 : 0)
        const plugins = Array.from({ length: count }, (_, index) => ({
          name: `bad-${index}`, publisher: "acme", url: `/plugins/acme/bad-${index}`,
          category: "other", summary: "bad", kinds: [], tags: [], preview: null
        }))
        return Promise.resolve(new Response(JSON.stringify({
          schema_version: 1,
          query: {
            q,
            sort: q === "wrong-context" ? "downloads" : "name",
            category: q === "wrong-context" ? "widgets" : null,
            tag: q === "wrong-context" ? "clock" : null
          },
          page: { number: 1, per_page: 9, total, more: total > 9 },
          plugins
        }), { status: 200, headers: { "Content-Type": "application/json" } }))
      }
    JS

    %w[malformed bad-metadata underfilled wrong-context oversized-body unstreamed].each do |query|
      page.execute_script("document.querySelector('[data-index-picker-target~=live]').textContent = ''")
      find("input[name='q']").set(query)
      assert_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
      assert_selector ".index-picker[data-search-stale='true']"
      assert_selector ".index-search__result[data-state='stale']", text: "—"
      assert_selector ".index-picker__row", count: 3
      assert_selector ".index-picker__card", count: HomeController::PER_PAGE
      assert_selector ".recent-band:not([hidden])"
      assert_current_path root_path(sort: "name")
    end
  end

  test "Enter performs a full-page fallback after live Search becomes stale" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.fetch = (url, options = {}) => {
        if (new URL(url).searchParams.get("q") === "fallback-query") {
          return Promise.resolve({ ok: true, headers: new Headers(), body: null })
        }
        return window.__realFetch(url, options)
      }
    JS

    search = find("input[name='q']")
    search.set("fallback-query")
    assert_selector ".index-picker[data-search-stale='true']"
    search.send_keys(:enter)

    assert_current_path root_path(q: "fallback-query", sort: "name")
    assert_field "q", with: "fallback-query"
    assert_no_selector ".index-picker[data-search-stale='true']"
    assert_selector ".index-search__result[data-state='live']", text: "0"
  end

  test "an empty live result clears selection announcements" do
    visit root_path(sort: "name")
    find("input[name='q']").set("no-such-plugin")

    assert_selector ".index-picker__row", count: 0
    assert_selector ".index-picker__card", count: HomeController::PER_PAGE
    assert_selector ".index-search__result[data-state='live']", text: "0"
    assert_selector ".index-browse__range", text: /0–0.*\/.*0/m
    assert_selector "[data-index-picker-target='live']", text: "No plugins match this search.", visible: :all
  end

  test "operator search opens a Browse level and backspace moves up" do
    visit root_path(sort: "name")

    find("input[name='q']").set("kind:bar-widget")
    assert_selector ".index-search__result[data-state='live']", text: "1"
    assert_selector ".index-browse__range", text: /1–1.*\/.*1/m
    assert_no_selector ".index-query-plan"
    assert_selector ".index-console--has-context"
    assert_selector ".index-picker__card", count: HomeController::PER_PAGE

    find("body").send_keys(:backspace)
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-console--has-context"
    assert_selector ".index-picker__row", count: 3

    find("input[name='q']").set('plugin:""')
    assert_selector ".index-picker__card-foot", count: 3
    assert_no_selector ".index-picker__card-foot", text: /(?:text|plugin):/

    [ "@", '@""', "author:@", 'author:"@"' ].each do |empty_author|
      find("input[name='q']").set(empty_author)
      assert_selector ".index-picker__row", count: 3
      assert_no_selector ".index-picker__card-foot", text: /(?:author|text):/
    end
  end

  test "Search depth changes replace cards without moving or animating them" do
    visit root_path(sort: "name")
    search = find("input[name='q']")
    search.set("clock")
    assert_selector ".index-search.is-active"
    assert_no_selector ".index-query-plan"
    assert_selector ".index-search__suggestions:not([hidden])"
    assert_equal({ "animation" => "none", "transform" => "none", "transition" => nil },
      page.evaluate_script(<<~JS))
        (() => {
          const picker = document.querySelector(".index-picker")
          const style = getComputedStyle(picker)
          return {
            animation: style.animationName,
            transform: style.transform,
            transition: picker.dataset.levelTransition || null
          }
        })()
      JS

    search.send_keys(:escape)
    assert_field "q", with: "clock"
    assert_no_selector ".index-search__suggestions"
    page.execute_script <<~JS
      window.__realFetch = window.fetch
      window.__returnCard = document.querySelector(".index-picker__card")
      window.__returnLeft = window.__returnCard.getBoundingClientRect().left
      window.__returnTop = window.__returnCard.getBoundingClientRect().top
      window.fetch = (url, options = {}) => {
        if (new URL(url).searchParams.get("q")) return window.__realFetch(url, options)
        return new Promise((resolve, reject) => {
          const timer = window.setTimeout(() => window.__realFetch(url, options).then(resolve, reject), 300)
          options.signal?.addEventListener("abort", () => {
            window.clearTimeout(timer)
            reject(new DOMException("Aborted", "AbortError"))
          }, { once: true })
        })
      }
    JS
    search.send_keys(:escape)
    sleep 0.08
    pending_motion = page.evaluate_script <<~JS
      (() => {
        const card = document.querySelector(".index-picker__card")
        const pickerStyle = getComputedStyle(document.querySelector(".index-picker"))
        return {
          sameCard: card === window.__returnCard,
          left: card.getBoundingClientRect().left - window.__returnLeft,
          top: card.getBoundingClientRect().top - window.__returnTop,
          animation: pickerStyle.animationName,
          transform: pickerStyle.transform
        }
      })()
    JS
    assert pending_motion["sameCard"]
    assert_in_delta 0, pending_motion["left"], 0.1
    assert_in_delta 0, pending_motion["top"], 0.1
    assert_equal "none", pending_motion["animation"]
    assert_equal "none", pending_motion["transform"]
    assert_selector ".index-search:not(.is-active)"
    assert_current_path root_path(sort: "name")
    assert_equal({ "animation" => "none", "transform" => "none", "transition" => nil },
      page.evaluate_script(<<~JS))
        (() => {
          const picker = document.querySelector(".index-picker")
          const style = getComputedStyle(picker)
          return {
            animation: style.animationName,
            transform: style.transform,
            transition: picker.dataset.levelTransition || null
          }
        })()
      JS
  end

  test "mobile browse compacts controls, exposes two filter rows, and aligns terminal navigation" do
    publisher = Publisher.find_by!(name: "acme")
    [
      [ "mobile-desktop", "desktop", [] ],
      [ "mobile-development", "developer-tools", [] ],
      [ "mobile-hardware", "hardware", [] ],
      [ "mobile-productivity", "productivity", [] ],
      [ "mobile-security", "other", [ "security" ] ],
      [ "mobile-widgets-one", "widgets", [] ],
      [ "mobile-widgets-two", "widgets", [] ]
    ].each_with_index do |(plugin_name, category, tags), index|
      plugin = Plugin.create!(publisher:, name: plugin_name, summary: "Mobile layout fixture", category:,
        kinds: [ "theme" ], tags:, latest_version: "1.0.0", downloads_count: 20 - index)
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 3).to_s * 64,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(q: "clock", sort: "name")
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script(<<~JS)
        document.querySelector(".index-picker").dataset.indexPickerPerPageValue === "6" &&
          document.querySelectorAll(".index-picker__card").length === 6
      JS
    end

    metrics = page.evaluate_script <<~JS
      (() => {
        const picker = document.querySelector(".index-picker")
        const card = document.querySelector(".index-picker__card")
        const name = document.querySelector(".index-picker__card-name")
        const searchForm = document.querySelector(".index-search__form").getBoundingClientRect()
        const searchEntry = document.querySelector(".index-search__entry").getBoundingClientRect()
        const controls = [
          ".index-search__result", ".index-search__clear", ".index-search__reset", ".index-search__filter-toggle"
        ].map((selector) => document.querySelector(selector).getBoundingClientRect())
        const heroHeadElement = document.querySelector(".fetch__head")
        const heroHead = heroHeadElement.getBoundingClientRect()
        const heroItems = [ ".fetch__head strong", ".fetch__metric-label" ]
          .map((selector) => document.querySelector(selector).getBoundingClientRect())
        const heroCenter = (item) => (item.top + item.bottom) / 2
        const heroBefore = getComputedStyle(heroHeadElement, "::before")
        const heroAfter = getComputedStyle(heroHeadElement, "::after")
        return {
          layersHidden: [...document.querySelectorAll(".index-browse-layer, .index-picker__layer-head")]
            .every((element) => getComputedStyle(element).display === "none"),
          pickerBorder: parseFloat(getComputedStyle(picker).borderTopWidth),
          pickerShadow: getComputedStyle(picker).boxShadow,
          cardHeight: card.getBoundingClientRect().height,
          nameSize: parseFloat(getComputedStyle(name).fontSize),
          recentArtOpacity: getComputedStyle(document.querySelector(".recent-card__art")).opacity,
          cards: document.querySelectorAll(".index-picker__card").length,
          statusLeftHidden: getComputedStyle(document.querySelector(".index-picker__status-left")).display === "none",
          keyHintsHidden: getComputedStyle(document.querySelector(".index-picker__keys")).display === "none",
          searchOneRow: [ searchEntry, ...controls ].every((item) =>
            Math.abs((item.top + item.bottom) / 2 - (searchForm.top + searchForm.bottom) / 2) < 0.5),
          searchCompact: searchForm.height <= 52,
          searchControlsDistinct: controls.every((control, index) => controls.slice(index + 1)
            .every((other) => control.right <= other.left || other.right <= control.left)),
          heroItemsCentered: heroItems.every((item) => Math.abs(heroCenter(item) - heroCenter(heroHead)) < 0.5),
          heroClusterCentered: Math.abs((heroItems[0].left + heroItems[1].right) / 2 -
            (heroHead.left + heroHead.right) / 2) < 0.5,
          heroLabelBesideCount: heroItems[1].left >= heroItems[0].right,
          heroLabelText: document.querySelector(".fetch__metric-label").innerText.trim(),
          heroTypographyMatched: Math.abs(
            parseFloat(getComputedStyle(document.querySelector(".fetch__head strong")).fontSize) -
            parseFloat(getComputedStyle(document.querySelector(".fetch__metric-label")).fontSize)) < 0.1,
          heroLinesRemoved: heroBefore.content === "none" && heroAfter.content === "none",
          heroSloganRemoved: document.querySelector(".fetch__mobile-message") === null,
          heroCompact: document.querySelector(".fetch").getBoundingClientRect().height <= 52,
          heroRuleHidden: getComputedStyle(document.querySelector(".fetch__rule")).display === "none",
          heroInside: heroItems.every((item) => item.left >= heroHead.left && item.right <= heroHead.right),
          compactMetricVisible: getComputedStyle(document.querySelector(".fetch__cluster")).display === "flex",
          compactLogoRemoved: document.querySelector(".fetch__mobile-logo") === null,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS

    assert metrics["layersHidden"]
    assert_equal 0, metrics["pickerBorder"]
    assert_equal "none", metrics["pickerShadow"]
    assert_in_delta 276, metrics["cardHeight"], 0.5
    assert_operator metrics["nameSize"], :>=, 13
    assert_equal "1", metrics["recentArtOpacity"]
    assert_equal 6, metrics["cards"]
    assert metrics["statusLeftHidden"]
    assert metrics["keyHintsHidden"]
    assert metrics["searchOneRow"]
    assert metrics["searchCompact"]
    assert metrics["searchControlsDistinct"]
    assert metrics["heroItemsCentered"]
    assert metrics["heroClusterCentered"]
    assert metrics["heroLabelBesideCount"]
    assert_equal "community plugins", metrics["heroLabelText"].downcase
    assert metrics["heroTypographyMatched"]
    assert metrics["heroLinesRemoved"]
    assert metrics["heroSloganRemoved"]
    assert metrics["heroCompact"]
    assert metrics["heroRuleHidden"]
    assert metrics["heroInside"]
    assert metrics["compactMetricVisible"]
    assert metrics["compactLogoRemoved"]
    assert_equal 0, metrics["overflow"]

    find(".index-search__filter-toggle").click
    assert_selector ".index-console.is-filter-open .index-picker__layer-head"
    filter_layout = page.evaluate_script <<~JS
      (() => {
        const layer = document.querySelector(".index-picker__layer-head")
        const layerBox = layer.getBoundingClientRect()
        const scroller = layer.querySelector("[data-index-picker-target='visibleCategories']")
        const options = [...layer.querySelectorAll(".index-picker__filter-option")]
        const boxes = options.map((option) => option.getBoundingClientRect())
        const rows = [...new Set(boxes.map((box) => Math.round(box.top)))]
        return {
          options: options.length,
          rows: rows.length,
          touchTargets: boxes.every((box) => box.height >= 44),
          allInside: boxes.every((box) => box.left >= layerBox.left && box.right <= layerBox.right &&
            box.top >= layerBox.top && box.bottom <= layerBox.bottom),
          contentInside: options.every((option) => {
            const content = option.querySelector("span")
            return content.scrollWidth - content.clientWidth <= 0.5
          }),
          internalOverflow: scroller.scrollWidth - scroller.clientWidth,
          pageOverflow: document.documentElement.scrollWidth - document.documentElement.clientWidth,
          optionFont: parseFloat(getComputedStyle(options[0]).fontSize),
          toggleFont: parseFloat(getComputedStyle(document.querySelector(".index-search__filter-toggle")).fontSize),
          duplicateLabel: Boolean(layer.querySelector(".index-picker__filter-label, .index-picker__filter-glyph"))
        }
      })()
    JS
    assert_equal 10, filter_layout["options"]
    assert_equal 2, filter_layout["rows"]
    assert filter_layout["touchTargets"]
    assert filter_layout["allInside"]
    assert filter_layout["contentInside"]
    assert_equal 0, filter_layout["internalOverflow"]
    assert_equal 0, filter_layout["pageOverflow"]
    assert_operator filter_layout["optionFont"], :>=, 8.5
    assert_operator filter_layout["optionFont"], :<=, filter_layout["toggleFont"]
    refute filter_layout["duplicateLabel"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 320, height: 900, deviceScaleFactor: 1, mobile: false)
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script(<<~JS)
        document.querySelector(".index-picker").dataset.indexPickerPerPageValue === "6" &&
          document.querySelectorAll(".index-picker__card").length === 6
      JS
    end
    narrow_layout = page.evaluate_script <<~JS
      (() => {
        const form = document.querySelector(".index-search__form").getBoundingClientRect()
        const items = [
          ".index-search__entry", ".index-search__result", ".index-search__clear",
          ".index-search__reset", ".index-search__filter-toggle"
        ].map((selector) => document.querySelector(selector).getBoundingClientRect())
        const options = [...document.querySelectorAll(".index-picker__filter-option")]
        const boxes = options.map((option) => option.getBoundingClientRect())
        const hero = document.querySelector(".fetch").getBoundingClientRect()
        const heroHeadElement = document.querySelector(".fetch__head")
        const heroHead = heroHeadElement.getBoundingClientRect()
        const heroItems = [ ".fetch__head strong", ".fetch__metric-label" ]
          .map((selector) => document.querySelector(selector).getBoundingClientRect())
        const centerY = (box) => (box.top + box.bottom) / 2
        const heroBefore = getComputedStyle(heroHeadElement, "::before")
        const heroAfter = getComputedStyle(heroHeadElement, "::after")
        const mostTitle = document.querySelector(".recent-band .boxtitle").getBoundingClientRect()
        const mostControls = document.querySelector(".recent-band__controls").getBoundingClientRect()
        const recentTitle = document.querySelector(".recent-stream .boxtitle").getBoundingClientRect()
        const recentControls = document.querySelector(".recent-stream__controls").getBoundingClientRect()
        const pageInput = document.querySelector(".index-picker__page input")
        const pageTotal = document.querySelector(".index-picker__page b")
        const originalPage = pageInput.value
        const originalTotal = pageTotal.textContent
        const originalDigits = pageInput.style.getPropertyValue("--page-digits")
        pageInput.value = "147"
        pageInput.style.setProperty("--page-digits", "3")
        pageTotal.textContent = "147"
        const pageFormBox = document.querySelector(".index-picker__page-form").getBoundingClientRect()
        const pageTotalBox = pageTotal.getBoundingClientRect()
        pageInput.value = originalPage
        pageTotal.textContent = originalTotal
        pageInput.style.setProperty("--page-digits", originalDigits)
        return {
          searchOneRow: items.every((item) =>
            Math.abs((item.top + item.bottom) / 2 - (form.top + form.bottom) / 2) < 0.5),
          searchDistinct: items.every((item, index) => items.slice(index + 1)
            .every((other) => item.right <= other.left || other.right <= item.left)),
          filterRows: new Set(boxes.map((box) => Math.round(box.top))).size,
          filterContentInside: options.every((option) => {
            const content = option.querySelector("span")
            return content.scrollWidth - content.clientWidth <= 0.5
          }),
          heroHeight: hero.height,
          heroItemsCentered: heroItems.every((item) => Math.abs(centerY(item) - centerY(heroHead)) < 0.5),
          heroClusterCentered: Math.abs((heroItems[0].left + heroItems[1].right) / 2 -
            (heroHead.left + heroHead.right) / 2) < 0.5,
          heroLabel: document.querySelector(".fetch__metric-label").innerText.trim(),
          heroLinesRemoved: heroBefore.content === "none" && heroAfter.content === "none",
          cards: document.querySelectorAll(".index-picker__card").length,
          perPage: Number(document.querySelector(".index-picker").dataset.indexPickerPerPageValue),
          mostWantedSingleLine: Math.abs((mostTitle.top + mostTitle.bottom) / 2 -
            (mostControls.top + mostControls.bottom) / 2) < 0.5,
          mostWantedCompact: getComputedStyle(document.querySelector(".recent-band__more")).display === "none" &&
            [...document.querySelectorAll(".recent-band__step-label")].every((label) => getComputedStyle(label).display === "none") &&
            [...document.querySelectorAll(".recent-band__step-label-short")].every((label) => getComputedStyle(label).display !== "none"),
          recentlyAddedSingleLine: Math.abs((recentTitle.top + recentTitle.bottom) / 2 -
            (recentControls.top + recentControls.bottom) / 2) < 0.5,
          recentlyAddedCompact: getComputedStyle(document.querySelector(".recent-stream__count")).display === "none" &&
            getComputedStyle(document.querySelector(".recent-stream__sort-prefix")).display === "none",
          threeDigitPageClearance: pageFormBox.right - pageTotalBox.right,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert narrow_layout["searchOneRow"]
    assert narrow_layout["searchDistinct"]
    assert_equal 2, narrow_layout["filterRows"]
    assert narrow_layout["filterContentInside"]
    assert_operator narrow_layout["heroHeight"], :>=, 32
    assert_operator narrow_layout["heroHeight"], :<=, 36
    assert narrow_layout["heroItemsCentered"]
    assert narrow_layout["heroClusterCentered"]
    assert_equal "community plugins", narrow_layout["heroLabel"].downcase
    assert narrow_layout["heroLinesRemoved"]
    assert_equal 6, narrow_layout["cards"]
    assert_equal 6, narrow_layout["perPage"]
    assert narrow_layout["mostWantedSingleLine"]
    assert narrow_layout["mostWantedCompact"]
    assert narrow_layout["recentlyAddedSingleLine"]
    assert narrow_layout["recentlyAddedCompact"]
    assert_operator narrow_layout["threeDigitPageClearance"], :>=, 8
    assert_equal 0, narrow_layout["overflow"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script(<<~JS)
        document.querySelector(".index-picker").dataset.indexPickerPerPageValue === "9" &&
          document.querySelectorAll(".index-picker__card").length === 9
      JS
    end
    intermediate_layout = page.evaluate_script <<~JS
      (() => {
        const hero = document.querySelector(".fetch").getBoundingClientRect()
        const heroHeadElement = document.querySelector(".fetch__head")
        const heroHead = heroHeadElement.getBoundingClientRect()
        const heroNumber = document.querySelector(".fetch__head strong").getBoundingClientRect()
        const heroLabel = document.querySelector(".fetch__metric-label").getBoundingClientRect()
        const heroBefore = getComputedStyle(heroHeadElement, "::before")
        const heroAfter = getComputedStyle(heroHeadElement, "::after")
        const status = document.querySelector(".index-picker__status").getBoundingClientRect()
        const pageForm = document.querySelector(".index-picker__page-form").getBoundingClientRect()
        const footerItems = [
          ".statusfoot__project", ".statusfoot__registry", ".statusfoot__trademark"
        ].map((selector) => document.querySelector(selector).getBoundingClientRect())
        const filterLayer = document.querySelector(".index-picker__layer-head").getBoundingClientRect()
        const filterBoxes = [...document.querySelectorAll(".index-picker__filter-option")]
          .map((option) => option.getBoundingClientRect())
        return {
          heroHeight: hero.height,
          desktopHeroMark: getComputedStyle(document.querySelector(".fetch__mark")).display,
          compactHeroLogoRemoved: document.querySelector(".fetch__mobile-logo") === null,
          heroClusterCentered: Math.abs((heroNumber.left + heroLabel.right) / 2 -
            (heroHead.left + heroHead.right) / 2) < 0.5,
          heroItemsCentered: [ heroNumber, heroLabel ].every((item) =>
            Math.abs((item.top + item.bottom) / 2 - (heroHead.top + heroHead.bottom) / 2) < 0.5),
          heroLinesRemoved: heroBefore.content === "none" && heroAfter.content === "none",
          heroSloganRemoved: document.querySelector(".fetch__mobile-message") === null,
          numberFont: parseFloat(getComputedStyle(document.querySelector(".fetch__head strong")).fontSize),
          labelFont: parseFloat(getComputedStyle(document.querySelector(".fetch__metric-label")).fontSize),
          labelText: document.querySelector(".fetch__metric-label").innerText.trim(),
          pluginLabelBeside: heroLabel.left >= heroNumber.right &&
            Math.abs((heroLabel.top + heroLabel.bottom) / 2 - (heroNumber.top + heroNumber.bottom) / 2) < 0.5,
          statusHeight: status.height,
          pageFormHeight: pageForm.height,
          pageCentered: Math.abs((pageForm.left + pageForm.right) / 2 - (status.left + status.right) / 2),
          statusLeft: getComputedStyle(document.querySelector(".index-picker__status-left")).display,
          keyHints: getComputedStyle(document.querySelector(".index-picker__keys")).display,
          filterRows: new Set(filterBoxes.map((box) => Math.round(box.top))).size,
          filtersContained: filterBoxes.every((box) => box.left >= filterLayer.left && box.right <= filterLayer.right &&
            box.top >= filterLayer.top && box.bottom <= filterLayer.bottom),
          footerAligned: footerItems.every((item) =>
            Math.abs((item.top + item.bottom) / 2 - (footerItems[0].top + footerItems[0].bottom) / 2) < 0.5),
          katakana: getComputedStyle(document.querySelector(".statusfoot__katakana")).display,
          mobileNavigation: getComputedStyle(document.querySelector(".mobile-nav")).display,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert_in_delta 35.6, intermediate_layout["heroHeight"], 0.5
    assert_equal "none", intermediate_layout["desktopHeroMark"]
    assert intermediate_layout["compactHeroLogoRemoved"]
    assert intermediate_layout["heroClusterCentered"]
    assert intermediate_layout["heroItemsCentered"]
    assert intermediate_layout["heroLinesRemoved"]
    assert intermediate_layout["heroSloganRemoved"]
    assert_in_delta intermediate_layout["numberFont"], intermediate_layout["labelFont"], 0.1
    assert_equal "community plugins", intermediate_layout["labelText"].downcase
    assert intermediate_layout["pluginLabelBeside"]
    assert_in_delta 50, intermediate_layout["statusHeight"], 0.1
    assert_in_delta 48, intermediate_layout["pageFormHeight"], 0.1
    assert_in_delta 0, intermediate_layout["pageCentered"], 0.1
    assert_equal "none", intermediate_layout["statusLeft"]
    assert_equal "none", intermediate_layout["keyHints"]
    assert_equal 2, intermediate_layout["filterRows"]
    assert intermediate_layout["filtersContained"]
    assert intermediate_layout["footerAligned"]
    assert_equal "none", intermediate_layout["katakana"]
    assert_equal "none", intermediate_layout["mobileNavigation"]
    assert_equal 0, intermediate_layout["overflow"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    Selenium::WebDriver::Wait.new(timeout: 3).until do
      page.evaluate_script(<<~JS)
        document.querySelector(".index-picker").dataset.indexPickerPerPageValue === "6" &&
          document.querySelectorAll(".index-picker__card").length === 6
      JS
    end
    find(".index-browse__sort summary").click
    assert_selector ".index-browse__sort.is-open .index-browse__sort-options a", count: HomeController::SORTS.size
    opening_layout = page.evaluate_script <<~JS
      (() => {
        const panel = document.querySelector(".index-browse__sort-options")
        return {
          transform: getComputedStyle(panel).transform,
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert_equal "none", opening_layout["transform"]
    assert_equal 0, opening_layout["overflow"]
    Selenium::WebDriver::Wait.new(timeout: 2).until do
      page.evaluate_script("getComputedStyle(document.querySelector('.index-browse__sort-options')).opacity") == "1"
    end
    sort_layout = page.evaluate_script <<~JS
      (() => {
        const options = [...document.querySelectorAll(".index-browse__sort-options a")]
          .map((link) => link.getBoundingClientRect())
        const panel = document.querySelector(".index-browse__sort-options").getBoundingClientRect()
        const search = document.querySelector(".index-search").getBoundingClientRect()
        const styleProperties = [
          "backgroundColor", "borderTopColor", "borderTopStyle", "boxShadow", "color",
          "fontFamily", "fontSize", "fontWeight", "letterSpacing", "lineHeight", "textTransform"
        ]
        const styles = (element) => {
          const style = getComputedStyle(element)
          return Object.fromEntries(styleProperties.map((property) => [property, style[property]]))
        }
        const filter = document.querySelector(".index-picker__filter-option")
        const normalFilter = styles(filter)
        filter.classList.add("is-active")
        filter.getAnimations().forEach((animation) => animation.finish())
        const activeFilter = styles(filter)
        filter.classList.remove("is-active")
        return {
          noOverlap: panel.bottom <= search.top,
          alignedLeft: Math.abs(panel.left - search.left),
          alignedRight: Math.abs(panel.right - search.right),
          targets: options.every((box) => box.width >= 44 && box.height >= 44),
          distinct: options.every((box, index) => options.slice(index + 1).every((other) =>
            box.right <= other.left || other.right <= box.left || box.bottom <= other.top || other.bottom <= box.top)),
          normalFilter,
          normalSort: styles([...document.querySelectorAll(".index-browse__sort a")]
            .find((link) => link.textContent.trim() === "downloads")),
          activeFilter,
          activeSort: styles(document.querySelector(".index-browse__sort a.is-active")),
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert sort_layout["noOverlap"]
    assert_in_delta 0, sort_layout["alignedLeft"], 0.1, sort_layout.inspect
    assert_in_delta 0, sort_layout["alignedRight"], 0.1, sort_layout.inspect
    assert sort_layout["targets"]
    assert sort_layout["distinct"]
    assert_equal sort_layout["normalFilter"], sort_layout["normalSort"]
    assert_equal sort_layout["activeFilter"], sort_layout["activeSort"]
    assert_equal 0, sort_layout["overflow"]

    visit root_path(sort: "name")
    assert_selector "[data-index-picker-target='next']"
    navigation_layout = page.evaluate_script <<~JS
      (() => {
        const center = (box) => (box.left + box.right) / 2
        const status = document.querySelector(".index-picker__status").getBoundingClientRect()
        const pageForm = document.querySelector(".index-picker__page-form").getBoundingClientRect()
        const nextLink = document.querySelector("[data-index-picker-target='next']")
        const nextBox = nextLink.getBoundingClientRect()
        const footerItems = [
          ".statusfoot__project", ".statusfoot__registry", ".statusfoot__trademark"
        ].map((selector) => document.querySelector(selector).getBoundingClientRect())
        return {
          pageCentered: Math.abs(center(pageForm) - center(status)),
          nextRight: Math.abs(nextBox.right - status.right),
          statusHeight: status.height,
          paginationHeight: document.querySelector(".index-picker__pagination").getBoundingClientRect().height,
          pageFormHeight: pageForm.height,
          pageSize: parseFloat(getComputedStyle(document.querySelector(".index-picker__page")).fontSize),
          arrowSize: parseFloat(getComputedStyle(nextLink).fontSize),
          pageTargetHeight: document.querySelector(".index-picker__page input").getBoundingClientRect().height,
          footerAligned: footerItems.every((item) =>
            Math.abs((item.top + item.bottom) / 2 - (footerItems[0].top + footerItems[0].bottom) / 2) < 0.5),
          footerDistinct: footerItems.every((item, index) => footerItems.slice(index + 1)
            .every((other) => item.right <= other.left || other.right <= item.left)),
          katakanaHidden: getComputedStyle(document.querySelector(".statusfoot__katakana")).display === "none",
          overflow: document.documentElement.scrollWidth - document.documentElement.clientWidth
        }
      })()
    JS
    assert_in_delta 0, navigation_layout["pageCentered"], 0.1
    assert_in_delta 1, navigation_layout["nextRight"], 0.1
    assert_in_delta 50, navigation_layout["statusHeight"], 0.1
    assert_in_delta 48, navigation_layout["paginationHeight"], 0.1
    assert_in_delta 48, navigation_layout["pageFormHeight"], 0.1
    assert_in_delta 13, navigation_layout["pageSize"], 0.1
    assert_in_delta 18, navigation_layout["arrowSize"], 0.1
    assert_operator navigation_layout["pageTargetHeight"], :>=, 44
    assert navigation_layout["footerAligned"]
    assert navigation_layout["footerDistinct"]
    assert navigation_layout["katakanaHidden"]
    assert_equal 0, navigation_layout["overflow"]

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 961, height: 900, deviceScaleFactor: 1, mobile: false)
    standard_layout = page.evaluate_script <<~JS
      (() => ({
        statusLeft: getComputedStyle(document.querySelector(".index-picker__status-left")).display,
        keyHints: getComputedStyle(document.querySelector(".index-picker__keys")).display,
        katakana: getComputedStyle(document.querySelector(".statusfoot__katakana")).display,
        heroRule: getComputedStyle(document.querySelector(".fetch__rule")).display
      }))()
    JS
    assert_equal "flex", standard_layout["statusLeft"]
    assert_equal "flex", standard_layout["keyHints"]
    assert_equal "inline", standard_layout["katakana"]
    refute_equal "none", standard_layout["heroRule"]
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "responsive page-size changes preserve pending and historical result anchors" do
    publisher = Publisher.find_by!(name: "acme")
    15.times do |index|
      plugin = Plugin.create!(publisher:, name: "responsive-#{index.to_s.rjust(2, '0')}",
        summary: "Responsive pagination fixture", latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 20).to_s(16).rjust(2, "0") * 32,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(q: "responsive-", sort: "name")
    assert_selector ".index-picker__row", count: 9
    initial_history = page.evaluate_script("history.state.turbo")

    page.execute_script <<~JS
      window.__realResponsiveFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const request = new URL(typeof url === "string" ? url : url.url, window.location.origin)
        if (request.searchParams.get("page") === "2" && request.searchParams.get("per_page") === "9") {
          return new Promise((resolve, reject) => {
            const delayed = { ...options, signal: undefined }
            window.setTimeout(() => window.__realResponsiveFetch(url, delayed).then(resolve, reject), 600)
          })
        }
        return window.__realResponsiveFetch(url, options)
      }
    JS

    find("a[aria-label='Next nine plugin results']").click
    assert_selector ".index-picker[aria-busy='true']"
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)

    assert_selector ".index-picker:not([aria-busy])"
    assert_selector ".index-picker__row", count: 6
    assert_selector ".index-picker__row.is-selected", text: "responsive-09"
    assert_selector ".index-browse__range", text: /7–12.*\/.*15/m
    assert_selector "a[aria-label='Next six plugin results']"
    assert_equal initial_history["restorationIndex"] + 1,
      page.evaluate_script("history.state.turbo.restorationIndex")
    assert_equal false, page.evaluate_script("history.state.registryBrowse.selectionCleared")
    assert_equal({ "q" => "responsive-", "sort" => "name", "page" => "2" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))

    page.go_back
    assert_equal({ "q" => "responsive-", "sort" => "name" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
    assert_equal 0, page.evaluate_script("history.state.registryBrowse.absoluteAnchor")
    assert_selector ".index-browse__range", text: /1–6.*\/.*15/m
    assert_no_selector ".index-picker__row.is-selected"

    page.go_forward
    assert_selector ".index-browse__range", text: /7–12.*\/.*15/m
    assert_equal({ "q" => "responsive-", "sort" => "name", "page" => "2" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))

    find("a[aria-label='Next six plugin results']").click
    assert_selector ".index-picker__row", count: 3
    assert_selector ".index-browse__range", text: /13–15.*\/.*15/m
    assert_equal({ "q" => "responsive-", "sort" => "name", "page" => "3" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    assert_selector ".index-picker:not([aria-busy])"
    assert_selector ".index-picker__row", count: 6
    assert_selector ".index-picker__row.is-selected", text: "responsive-12"
    assert_equal({ "q" => "responsive-", "sort" => "name", "page" => "2" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a cleared non-first-page window keeps its anchor across responsive page sizes" do
    publisher = Publisher.find_by!(name: "acme")
    15.times do |index|
      plugin = Plugin.create!(publisher:, name: "anchor-responsive-#{index.to_s.rjust(2, '0')}",
        summary: "Responsive anchor fixture", latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 60).to_s(16).rjust(2, "0") * 32,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(q: "anchor-responsive-", sort: "name", page: 2)
    assert_selector ".index-browse__range", text: /10–15.*\/.*15/m
    assert_no_selector ".index-picker__row.is-selected"

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    assert_selector ".index-browse__range", text: /7–12.*\/.*15/m
    assert_no_selector ".index-picker__row.is-selected"
    assert_equal 9, page.evaluate_script("history.state.registryBrowse.absoluteAnchor")

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    assert_selector ".index-browse__range", text: /10–15.*\/.*15/m
    assert_no_selector ".index-picker__row.is-selected"
    assert_equal 9, page.evaluate_script("history.state.registryBrowse.absoluteAnchor")
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "a compact history anchor survives a full reload and desktop remap" do
    publisher = Publisher.find_by!(name: "acme")
    15.times do |index|
      plugin = Plugin.create!(publisher:, name: "reload-responsive-#{index.to_s.rjust(2, '0')}",
        summary: "Responsive reload fixture", latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 80).to_s(16).rjust(2, "0") * 32,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(q: "reload-responsive-", sort: "name", page: 2)
    assert_selector ".index-browse__range", text: /7–12.*\/.*15/m

    find("body").send_keys(:arrow_down)
    3.times { find("body").send_keys(:arrow_down) }
    assert_selector ".index-picker__row.is-selected", text: "reload-responsive-09"
    assert_equal({ "perPage" => 6, "absoluteAnchor" => 9, "selectionCleared" => false },
      page.evaluate_script("history.state.registryBrowse"))

    page.refresh
    assert_selector ".index-browse__range", text: /7–12.*\/.*15/m
    assert_selector ".index-picker__row", count: 6
    assert_selector ".index-picker__row.is-selected", text: "reload-responsive-09"

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    assert_selector ".index-browse__range", text: /10–15.*\/.*15/m
    assert_selector ".index-picker__row.is-selected", text: "reload-responsive-09"
    assert_equal({ "q" => "reload-responsive-", "sort" => "name", "page" => "2" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "Turbo return remaps the cached Browse anchor across the compact breakpoint" do
    publisher = Publisher.find_by!(name: "acme")
    15.times do |index|
      plugin = Plugin.create!(publisher:, name: "return-responsive-#{index.to_s.rjust(2, '0')}",
        summary: "Responsive return fixture", latest_version: "1.0.0", category: "other")
      plugin.versions.create!(version: "1.0.0", manifest: {}, sha256: (index + 40).to_s(16).rjust(2, "0") * 32,
        size_bytes: 1024, state: :published, published_at: Time.current)
    end

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(q: "return-responsive-", sort: "name", page: 2)
    assert_selector ".index-picker__row", count: 6

    find("body").send_keys(:arrow_right)
    3.times { find("body").send_keys(:arrow_right) }
    assert_selector ".index-picker__row.is-selected", text: "return-responsive-12"
    assert_equal({ "absoluteAnchor" => 12, "selectionCleared" => false },
      page.evaluate_script("({ absoluteAnchor: history.state.registryBrowse.absoluteAnchor, selectionCleared: history.state.registryBrowse.selectionCleared })"))
    find(".index-picker__row.is-selected .index-picker__card-open").click
    assert_current_path plugin_path("acme", "return-responsive-12")

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    page.go_back

    assert_selector ".index-browse__range", text: /13–15.*\/.*15/m
    assert_selector ".index-picker__row", count: 3
    assert_selector ".index-picker__card", count: 6
    assert_selector ".index-picker__row.is-selected", text: "return-responsive-12"
    assert_equal({ "q" => "return-responsive-", "sort" => "name", "page" => "3" },
      Rack::Utils.parse_nested_query(URI(page.current_url).query))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "failed compact page-size negotiation keeps the authoritative nine-card window" do
    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 800, height: 900, deviceScaleFactor: 1, mobile: false)
    visit root_path(sort: "name")
    original_names = all(".index-picker__row .index-picker__card-name").map(&:text)
    assert_selector ".index-picker__card", count: 9

    page.execute_script <<~JS
      window.__realResponsiveFetch = window.fetch
      window.fetch = (url, options = {}) => {
        const request = new URL(url, window.location.origin)
        if (request.searchParams.get("per_page") === "6") {
          return new Promise((resolve) => window.setTimeout(() => resolve(new Response("{}", {
            status: 200, headers: { "Content-Type": "application/json" }
          })), 120))
        }
        return window.__realResponsiveFetch(url, options)
      }
    JS

    page.driver.browser.execute_cdp("Emulation.setDeviceMetricsOverride",
      width: 390, height: 900, deviceScaleFactor: 1, mobile: false)
    assert_selector ".index-picker[aria-busy='true']"
    assert_selector ".index-picker[data-search-stale='true']"
    assert_selector ".index-picker__card", count: 9
    assert_equal original_names, all(".index-picker__row .index-picker__card-name").map(&:text)
    assert_equal "9", find(".index-picker", visible: :all)["data-index-picker-per-page-value"]
    assert_equal({ "sort" => "name" }, Rack::Utils.parse_nested_query(URI(page.current_url).query))
  ensure
    page.driver.browser.execute_cdp("Emulation.clearDeviceMetricsOverride")
  end

  test "back and forward restore category browse context" do
    visit root_path(category: "widgets", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "alpha"
    assert_selector ".index-console--has-context.is-filter-open [data-index-picker-target='visibleCategories']", text: /widgets 1/i

    find("body").send_keys(:backspace)
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 3

    page.go_back
    assert_current_path root_path(category: "widgets", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "alpha"
    assert_selector ".index-console--has-context.is-filter-open [data-index-picker-target='visibleCategories']", text: /widgets 1/i

    page.go_forward
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 3
  end

  test "back and forward restore query, tag, and sort state" do
    visit root_path(q: "gamma", tag: "clock", sort: "name")
    assert_field "q", with: "gamma"
    assert_selector ".index-picker__row", count: 1, text: "gamma"
    initial_history = page.evaluate_script("history.state.turbo")

    find("input[name='q']").set("")
    assert_current_path root_path(tag: "clock", sort: "name")
    cleared_history = page.evaluate_script("history.state.turbo")
    refute_equal initial_history["restorationIdentifier"], cleared_history["restorationIdentifier"]
    assert_equal initial_history["restorationIndex"] + 1, cleared_history["restorationIndex"]
    assert_selector ".index-picker__row", count: 1, text: "gamma"

    page.go_back
    assert_current_path root_path(q: "gamma", tag: "clock", sort: "name")
    assert_equal initial_history, page.evaluate_script("history.state.turbo")
    assert_field "q", with: "gamma"
    assert_selector ".index-picker__row", count: 1, text: "gamma"

    page.go_forward
    assert_current_path root_path(tag: "clock", sort: "name")
    assert_equal cleared_history, page.evaluate_script("history.state.turbo")
    assert_field "q", with: ""
    assert_selector ".index-picker__row", count: 1, text: "gamma"
  end

  test "the six-card browser reflows without horizontal overflow at 320px" do
    page.driver.browser.manage.window.resize_to(320, 900)
    visit root_path(q: "clock", sort: "name")
    assert_selector ".index-picker__card", count: 6
    assert_equal "6", find(".index-picker", visible: :all)["data-index-picker-per-page-value"]
    assert_no_selector ".index-query-plan"

    metrics = page.evaluate_script <<~JS
      (() => {
        const width = document.documentElement.clientWidth
        const selectors = [".index-search", ".index-picker", ".index-picker__status"]
        return {
          overflow: document.documentElement.scrollWidth - width,
          inside: selectors.every((selector) => {
            const rect = document.querySelector(selector).getBoundingClientRect()
            return rect.left >= -0.5 && rect.right <= width + 0.5
          })
        }
      })()
    JS
    assert_equal 0, metrics["overflow"]
    assert metrics["inside"]
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  test "popstate removes unknown taxonomy filters before loading" do
    visit root_path(sort: "name")
    page.execute_script <<~JS
      history.pushState(history.state, "", "/?category=unknown&tag=unknown&sort=bogus")
      history.pushState(history.state, "", "/?sort=name")
    JS

    page.go_back
    assert_current_path root_path
    assert_selector ".index-picker__row", count: 3
    assert_no_selector ".index-console--has-context"
    assert_no_selector "[data-index-picker-target='live']", text: /Search could not be updated/, visible: :all
  end

  test "mobile arrow geometry follows the single card column" do
    page.driver.browser.manage.window.resize_to(600, 900)
    visit root_path(sort: "name")

    find(".index-picker__row", text: "alpha").find(".index-picker__card-open").send_keys(:arrow_down)
    assert_selector ".index-picker__row.is-selected", text: "beta"
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  test "escape clears live search without leaving the index" do
    visit root_path(sort: "name")

    search = find("input[name='q']")
    search.set("audio")
    assert_current_path root_path(q: "audio", sort: "name")
    assert_selector ".index-picker__row", count: 1, text: "beta"
    search.send_keys(:escape)
    search.send_keys(:escape)
    assert_field "q", with: ""
    assert_current_path root_path(sort: "name")
    assert_selector ".index-picker__row", count: 3
    assert_current_path root_path(sort: "name")
    assert_no_selector ".index-query-plan"
    assert_no_selector ".index-console--has-context"
  end
end

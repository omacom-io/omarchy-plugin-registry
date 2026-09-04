require "application_system_test_case"
require "vips"

# The copy affordance runs real JavaScript (Clipboard API with a selection
# fallback) — proven in a real headless Chrome, not stubbed.
class CopyButtonSystemTest < ApplicationSystemTestCase
  test "install command copies and confirms" do
    dev = User.create!(email_address: "dev@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "acme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "weather",
        tarball_bytes: TarballBuilder.build).call
    end

    visit plugin_path("acme", "weather")
    surfaces = page.evaluate_script <<~JS
      (() => {
        const install = document.querySelector(".install-cmd")
        const copy = install.querySelector(".copy-button")
        const tileProbe = document.createElement("span")
        const controlProbe = document.createElement("span")
        tileProbe.style.cssText = "position:fixed;background:var(--break);box-shadow:var(--shadow-tile)"
        controlProbe.style.cssText = "position:fixed;box-shadow:var(--shadow-control)"
        document.body.append(tileProbe, controlProbe)
        const result = {
          background: getComputedStyle(install).backgroundColor,
          expectedBackground: getComputedStyle(tileProbe).backgroundColor,
          installShadow: getComputedStyle(install).boxShadow,
          expectedInstallShadow: getComputedStyle(tileProbe).boxShadow,
          copyShadow: getComputedStyle(copy).boxShadow,
          expectedCopyShadow: getComputedStyle(controlProbe).boxShadow
        }
        tileProbe.remove()
        controlProbe.remove()
        return result
      })()
    JS
    assert_equal surfaces["expectedBackground"], surfaces["background"]
    assert_equal surfaces["expectedInstallShadow"], surfaces["installShadow"]
    assert_equal surfaces["expectedCopyShadow"], surfaces["copyShadow"]
    refute_equal "none", surfaces["installShadow"]
    refute_equal "none", surfaces["copyShadow"]

    within(".install-cmd") do
      assert_text "omarchy plugin add acme/weather"
      button = find("button.copy-button--labeled")
      assert_selector ".copy-button__copy-label", text: "COPY", visible: true
      assert_predicate button[:title], :blank?
      button.hover
      assert_selector ".copy-button__tooltip", text: "Copy install command", visible: true
      tooltip_theme = page.evaluate_script <<~JS
        (() => {
          const tooltip = document.querySelector(".copy-button__tooltip")
          const root = getComputedStyle(document.documentElement)
          return { background: getComputedStyle(tooltip).backgroundColor,
            expected: root.getPropertyValue("--cell-2").trim() }
        })()
      JS
      assert_equal "rgb(36, 40, 59)", tooltip_theme["background"]
      assert_equal "#24283b", tooltip_theme["expected"]

      button.click
      assert_selector "button.copy-button--done[aria-label='Install command copied']", text: "COPIED"
      assert_no_selector ".copy-button__copy-label", visible: true
      assert_selector ".copy-button__check", visible: true
      assert page.evaluate_script(
        "getComputedStyle(document.querySelector('.copy-button__done-label')).animationName === 'copy-confirm'")
      find("button.copy-button").hover
      assert_no_selector ".copy-button__tooltip", visible: true
      button.send_keys(:tab)
      page.driver.browser.action.key_down(:shift).send_keys(:tab).key_up(:shift).perform
      assert page.evaluate_script("document.activeElement.matches('.copy-button--done:focus-visible')")
      assert_no_selector ".copy-button__tooltip", visible: true
      alignment = page.evaluate_script <<~JS
        (() => {
          const button = document.querySelector(".copy-button--labeled")
          const label = document.querySelector(".copy-button__done-label")
          const icon = document.querySelector(".copy-button__check")
          const center = (element) => { const rect = element.getBoundingClientRect(); return rect.top + rect.height / 2 }
          return { color: getComputedStyle(icon).color, fontSize: getComputedStyle(label).fontSize,
            height: button.getBoundingClientRect().height, centerDelta: Math.abs(center(label) - center(icon)),
            shadow: getComputedStyle(button).boxShadow,
            installShadow: getComputedStyle(document.querySelector(".install-cmd")).boxShadow }
        })()
      JS
      assert_equal "rgb(122, 162, 247)", alignment["color"]
      assert_equal "11px", alignment["fontSize"]
      assert_operator alignment["height"], :>=, 30
      assert_operator alignment["centerDelta"], :<=, 1
      assert_equal surfaces["copyShadow"], alignment["shadow"]
      assert_equal surfaces["installShadow"], alignment["installShadow"]
    end
  end

  test "plugin preview opens and closes its zoom dialog" do
    dev = User.create!(email_address: "preview@example.com", name: "Preview Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "previewco", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    preview = Vips::Image.black(640, 480).add(80).cast("uchar").pngsave_buffer
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "clock",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(id: "previewco.clock"),
          files: { "Widget.qml" => "import QtQuick\nItem {}\n", "preview.png" => preview }
        )).call
    end

    visit plugin_path("previewco", "clock")
    find("button.plugin-preview", text: "zoom ↗").click
    assert_selector "dialog.lightbox[open]"
    find("dialog.lightbox[open]").send_keys(:backspace)
    assert_current_path plugin_path("previewco", "clock")
    assert_selector "dialog.lightbox[open]"
    find("dialog.lightbox[open]").send_keys(:escape)
    assert_no_selector "dialog.lightbox[open]"
  end

  test "readme code blocks get an injected copy control" do
    dev = User.create!(email_address: "dev2@example.com", name: "Dev",
      otp_secret: ROTP::Base32.random, otp_enabled_at: Time.current)
    publisher = Publisher.create!(name: "bcme", kind: :org)
    Membership.create!(publisher:, user: dev, role: :owner, founding: true)
    readme = "# Widget

Great widget.

## Config

```
widget --set theme=tokyo-night
```
"
    perform_enqueued_jobs do
      Registry::PublishVersion.new(user: dev, publisher:, plugin_name: "widget",
        tarball_bytes: TarballBuilder.build(
          manifest: TarballBuilder.manifest(id: "bcme.widget"),
          files: { "Widget.qml" => "import QtQuick
Item {}
", "README.md" => readme }
        )).call
    end

    visit plugin_path("bcme", "widget")
    within(".readme .codeblock") do
      find("button.copy-button--floating").click
      assert_selector "button.copy-button--done"
    end
  end
end

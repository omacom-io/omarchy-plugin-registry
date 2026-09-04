import { Controller } from "@hotwired/stimulus"

const KEY = "registry-theme"
const MODE_KEY = "registry-theme-mode"
const SYSTEM_CACHE_KEY = "registry-system-theme"
const OVERRIDE_REVISION_KEY = "registry-theme-override-revision"
const PRESET = /^[a-z0-9-]{1,64}$/
const THEME_NAME = /^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$/
const HEX = /^#[0-9a-f]{6}$/
const WHEEL_STEP = 60
const SYNC_INTERVAL = 1000
const SYNC_TIMEOUT = 800
const MAX_SYNC_BYTES = 4096
const COLOR_KEYS = ["background", "foreground", "cursor", ...Array.from({ length: 16 }, (_, index) => `color${index}`)]
const LIVE_PROPERTIES = [
  "--bg", "--cell", "--cell-2", "--text", "--text-soft", "--text-muted", "--faint",
  "--line", "--line-strong", "--accent", "--accent-soft", "--on-accent", "--success",
  "--warning", "--danger", "--success-soft", "--warning-soft", "--danger-soft", "--info",
  "--cyan", "--magenta", "--break", "--ansi-00-slot", "--ansi-01-slot", "--ansi-02-slot",
  "--ansi-03-slot", "--ansi-04-slot", "--ansi-05-slot", "--ansi-06-slot", "--ansi-07-slot",
  "--ansi-08-slot", "--ansi-09-slot", "--ansi-10-slot", "--ansi-11-slot", "--ansi-12-slot",
  "--ansi-13-slot", "--ansi-14-slot", "--ansi-15-slot", "--terminal-cursor", "--accent-ink", "--cyan-ink", "--danger-ink",
  "--search-accent-ink", "--terminal-accent-readable", "--terminal-success-readable",
  "--terminal-warning-readable", "--terminal-muted-readable"
]

export default class extends Controller {
  static targets = ["option", "bar", "toggle", "toggleLabel", "mobileToggleLabel", "strip", "label"]
  static values = { omarchyUrl: String }

  connect() {
    this.selected = 0
    this.wheelAcc = 0
    this.loaded = false
    this.omarchyRevision = null
    this.appliedOmarchyRevision = null
    this.omarchyPayload = this.cachedOmarchyPayload()
    this.omarchyRevision = this.omarchyPayload?.revision || null
    this.omarchyRequest = null
    this.mode = this.storedMode()

    this.onKeydown = (event) => {
      if (![ "Escape", "Enter", "ArrowLeft", "ArrowRight" ].includes(event.key)) return
      if (event.key === "Escape") {
        event.preventDefault()
        event.stopPropagation()
        this.cancel({ restoreFocus: true })
        return
      }
      if (!this.barTarget.contains(event.target) || event.target.closest("input, textarea, select, [contenteditable]")) return

      event.preventDefault()
      event.stopPropagation()
      if (event.key === "Enter") this.apply({ restoreFocus: true })
      else this.move(event.key === "ArrowLeft" ? -1 : 1)
    }
    this.onDocClick = (event) => {
      if (this.barTarget.contains(event.target) || this.toggleTarget.contains(event.target)) return
      this.cancel()
    }
    this.onResize = () => {
      if (!this.barTarget.hidden) {
        this.loadPreviews()
        this.layout()
        if (this.compactPicker()) this.focusOption(this.optionTargets[this.selected])
      }
    }
    this.beforeCache = () => {
      if (!this.barTarget.hidden) this.cancel()
    }
    this.onVisibilityChange = () => {
      if (!document.hidden) this.pollOmarchyTheme()
    }
    window.addEventListener("resize", this.onResize)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    if (this.mode === "system" && this.omarchyPayload) {
      this.renderOmarchyTheme(this.omarchyPayload)
      this.appliedOmarchyRevision = this.omarchyPayload.revision
    }
    this.reflect()
    this.connectOmarchySync()
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onDocClick)
    window.removeEventListener("resize", this.onResize)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    window.clearInterval(this.omarchyTimer)
    this.omarchyRequest?.abort()
  }

  toggle() {
    if (this.barTarget.hidden) {
      this.open()
    } else {
      this.cancel()
    }
  }

  open() {
    this.loadPreviews()
    this.committed = document.documentElement.dataset.theme || "tokyo-night"
    this.committedMode = this.mode
    const selectedValue = this.mode === "system" ? "system" : this.committed
    const index = this.optionTargets.findIndex((option) => (option.dataset.themeValue || "") === selectedValue)
    this.selected = index < 0 ? 0 : index
    this.barTarget.hidden = false
    this.toggleTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("keydown", this.onKeydown)
    document.addEventListener("click", this.onDocClick)
    this.preview()
    this.layout()
    this.focusOption(this.optionTargets[this.selected])
    requestAnimationFrame(() => this.barTarget.classList.add("theme-picker--ready"))
  }

  close() {
    this.barTarget.hidden = true
    this.barTarget.classList.remove("theme-picker--ready")
    this.toggleTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("keydown", this.onKeydown)
    document.removeEventListener("click", this.onDocClick)
  }

  apply({ restoreFocus = false } = {}) {
    const option = this.optionTargets[this.selected]
    if (!option || option.disabled) return

    const theme = option.dataset.themeValue || "tokyo-night"
    if (theme === "system") {
      this.mode = "system"
      try {
        localStorage.setItem(MODE_KEY, "system")
        localStorage.removeItem(KEY)
        localStorage.removeItem(OVERRIDE_REVISION_KEY)
      } catch {
      }
      if (this.omarchyPayload) {
        this.renderOmarchyTheme(this.omarchyPayload)
        this.appliedOmarchyRevision = this.omarchyPayload.revision
      }
    } else {
      this.mode = "manual"
      this.applyTheme(theme)
      try {
        localStorage.setItem(MODE_KEY, "manual")
        localStorage.setItem(KEY, theme)
        localStorage.removeItem(OVERRIDE_REVISION_KEY)
      } catch {
      }
    }
    this.reflect()
    this.close()
    if (restoreFocus) this.toggleTarget.focus({ preventScroll: true })
  }

  cancel({ restoreFocus = false } = {}) {
    this.mode = this.committedMode || this.mode
    if (this.mode === "system" && this.omarchyPayload) {
      this.renderOmarchyTheme(this.omarchyPayload)
    } else if (this.committed === "omarchy-live" && this.omarchyPayload) {
      this.applyLiveTheme(this.omarchyPayload)
    } else {
      this.applyTheme(this.committed || "tokyo-night")
    }
    this.reflect()
    this.close()
    if (restoreFocus) this.toggleTarget.focus({ preventScroll: true })
  }

  pick(event) {
    if (event.currentTarget.disabled) return
    const index = this.optionTargets.indexOf(event.currentTarget)
    if (index < 0) return
    if (this.compactPicker()) {
      this.selected = index
      this.preview()
      this.apply({ restoreFocus: true })
    } else if (index === this.selected) {
      this.apply({ restoreFocus: true })
    } else {
      this.selected = index
      this.preview()
      this.layout()
    }
  }

  move(direction) {
    const count = this.optionTargets.length
    if (!count) return

    for (let offset = 1; offset <= count; offset += 1) {
      const index = (this.selected + direction * offset + count * offset) % count
      if (this.optionTargets[index].disabled) continue
      this.selected = index
      this.preview()
      this.layout()
      this.focusOption(this.optionTargets[this.selected])
      return
    }
  }

  wheel(event) {
    event.preventDefault()
    this.wheelAcc += event.deltaY + event.deltaX
    if (Math.abs(this.wheelAcc) >= WHEEL_STEP) {
      this.move(this.wheelAcc > 0 ? 1 : -1)
      this.wheelAcc = 0
    }
  }

  preview({ focus = false } = {}) {
    const option = this.optionTargets[this.selected]
    const theme = option.dataset.themeValue || "tokyo-night"
    const label = this.optionLabel(option)
    if (theme === "system" && this.omarchyPayload) this.renderOmarchyTheme(this.omarchyPayload)
    else if (theme !== "system") this.applyTheme(theme)
    if (this.hasLabelTarget) this.labelTarget.textContent = `Previewing ${label}`
    this.optionTargets.forEach((other, index) => {
      const selected = index === this.selected
      other.classList.toggle("theme-picker__item--selected", selected)
      other.tabIndex = selected ? 0 : -1
    })
    if (focus && !this.barTarget.hidden) this.focusOption(option)
  }

  layout() {
    if (this.compactPicker()) {
      const inlineProperties = [ "left", "top", "width", "height", "z-index" ]
      this.stripTarget.style.removeProperty("height")
      this.optionTargets.forEach((option) => {
        option.hidden = false
        inlineProperties.forEach((property) => option.style.removeProperty(property))
      })
      return
    }

    const viewWidth = this.stripTarget.clientWidth || window.innerWidth
    const expandedWidth = Math.min(230, Math.round(viewWidth * 0.22))
    const expandedHeight = Math.round(expandedWidth * 0.62)
    const sliceWidth = Math.max(26, Math.round(expandedWidth * 0.16))
    const sliceHeight = Math.round(expandedHeight * 0.91)
    const step = Math.round(sliceWidth * 0.72)
    const spacing = step - sliceWidth
    const previewX = Math.round((viewWidth - expandedWidth) / 2)
    const sliceTop = Math.round((expandedHeight - sliceHeight) / 2)

    this.stripTarget.style.height = expandedHeight + "px"
    this.optionTargets.forEach((option, index) => {
      const rel = index - this.selected
      const isSelected = rel === 0
      let x
      if (isSelected) {
        x = previewX
      } else if (rel < 0) {
        x = previewX + rel * step
      } else {
        x = previewX + expandedWidth + spacing + (rel - 1) * step
      }
      option.style.left = x + "px"
      option.style.top = (isSelected ? 0 : sliceTop) + "px"
      option.style.width = (isSelected ? expandedWidth : sliceWidth) + "px"
      option.style.height = (isSelected ? expandedHeight : sliceHeight) + "px"
      option.style.zIndex = isSelected ? 100 : 50 - Math.min(Math.abs(rel), 40)
      option.hidden = Math.abs(rel) > 20
    })
  }

  applyTheme(theme) {
    if (!PRESET.test(theme)) return
    this.clearLivePalette()
    document.documentElement.dataset.theme = theme
    this.syncThemeColor()
  }

  reflect() {
    const systemOption = this.optionTargets.find((option) => option.dataset.themeValue === "system")
    if (systemOption) systemOption.disabled = !this.hasOmarchyUrlValue && !this.omarchyPayload

    if (this.mode === "system") {
      const systemName = this.omarchyPayload?.name || "waiting"
      this.reflectToggle(`system/${systemName}`, systemName === "waiting" ? "system" : systemName)
      this.optionTargets.forEach((option) => {
        option.setAttribute("aria-pressed", option.dataset.themeValue === "system" ? "true" : "false")
      })
      this.syncThemeColor()
      return
    }

    let current = document.documentElement.dataset.theme || "tokyo-night"
    let selected = this.optionTargets.find((option) => option.dataset.themeValue === current)
    if (!selected || current === "system") {
      current = "tokyo-night"
      this.applyTheme(current)
      selected = this.optionTargets.find((option) => option.dataset.themeValue === current)
    }
    this.reflectToggle(this.optionLabel(selected))
    this.optionTargets.forEach((option) => {
      option.setAttribute("aria-pressed", option.dataset.themeValue === current ? "true" : "false")
    })
    this.syncThemeColor()
  }

  focusOption(option) {
    if (!option) return
    const compact = this.compactPicker()
    option.focus({ preventScroll: !compact })
    if (compact) option.scrollIntoView({ block: "nearest" })
  }

  reflectToggle(label, compactLabel = label) {
    if (this.hasToggleLabelTarget) this.toggleLabelTarget.textContent = label
    if (this.hasMobileToggleLabelTarget) this.mobileToggleLabelTarget.textContent = compactLabel
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-label", `Choose color theme; current ${label}`)
  }

  compactPicker() {
    return window.matchMedia("(max-width: 760px)").matches
  }

  loadPreviews() {
    if (this.loaded || this.compactPicker()) return
    this.loaded = true
    this.barTarget.querySelectorAll("img[data-src]").forEach((img) => { img.src = img.dataset.src })
  }

  optionLabel(option) {
    if (!option) return "tokyo-night"
    if (option.dataset.themeValue === "system") return `system/${this.omarchyPayload?.name || "waiting"}`
    return option.dataset.themeLabel || option.querySelector("img")?.alt || "tokyo-night"
  }

  storedMode() {
    const systemAvailable = this.hasOmarchyUrlValue || Boolean(this.omarchyPayload)
    try {
      const stored = localStorage.getItem(MODE_KEY)
      if (stored === "manual") return stored
      if (stored === "system") {
        const mode = systemAvailable ? "system" : "manual"
        if (mode !== stored) localStorage.setItem(MODE_KEY, mode)
        return mode
      }
      const legacyTheme = localStorage.getItem(KEY)
      const hasLegacyTheme = this.optionTargets.some((option) =>
        option.dataset.themeValue !== "system" && option.dataset.themeValue === legacyTheme)
      const mode = hasLegacyTheme || localStorage.getItem(OVERRIDE_REVISION_KEY) ? "manual" :
        (systemAvailable ? "system" : "manual")
      localStorage.setItem(MODE_KEY, mode)
      return mode
    } catch {
      return systemAvailable ? "system" : "manual"
    }
  }

  cachedOmarchyPayload() {
    try {
      return this.normalizedOmarchyPayload(JSON.parse(localStorage.getItem(SYSTEM_CACHE_KEY) || "null"))
    } catch {
      return null
    }
  }

  cacheOmarchyPayload(payload) {
    try {
      localStorage.setItem(SYSTEM_CACHE_KEY, JSON.stringify(payload))
    } catch {
    }
  }

  connectOmarchySync() {
    if (!this.hasOmarchyUrlValue) return
    let endpoint
    try {
      endpoint = new URL(this.omarchyUrlValue, window.location.origin)
    } catch {
      return
    }
    if (endpoint.origin !== window.location.origin) return

    this.omarchyEndpoint = endpoint.href
    this.pollOmarchyTheme()
    this.omarchyTimer = window.setInterval(() => this.pollOmarchyTheme(), SYNC_INTERVAL)
  }

  async pollOmarchyTheme() {
    if (!this.omarchyEndpoint || this.omarchyRequest || document.hidden) return
    const request = new AbortController()
    this.omarchyRequest = request
    const timeout = window.setTimeout(() => request.abort(), this.omarchyTimeout || SYNC_TIMEOUT)

    try {
      const response = await fetch(this.omarchyEndpoint, {
        headers: { Accept: "application/json" },
        cache: "no-store",
        credentials: "same-origin",
        signal: request.signal
      })
      if (response.status === 204) return
      if (!response.ok || !response.headers.get("content-type")?.toLowerCase().startsWith("application/json")) return
      const declaredLength = Number(response.headers.get("content-length"))
      if (Number.isFinite(declaredLength) && declaredLength > MAX_SYNC_BYTES) return

      const text = await this.readBoundedResponse(response)
      if (text === null) return
      const payload = this.normalizedOmarchyPayload(JSON.parse(text))
      if (!payload || request.signal.aborted || !this.element.isConnected) return

      this.omarchyRevision = payload.revision
      this.omarchyPayload = payload
      this.cacheOmarchyPayload(payload)
      if (!this.barTarget.hidden) {
        if (this.optionTargets[this.selected]?.dataset.themeValue === "system") this.preview()
        return
      }
      this.reflect()
      if (this.mode !== "system" || this.appliedOmarchyRevision === payload.revision) return

      this.applyOmarchyTheme(payload)
    } catch (error) {
      if (error.name !== "AbortError") return
    } finally {
      window.clearTimeout(timeout)
      if (this.omarchyRequest === request) this.omarchyRequest = null
    }
  }

  async readBoundedResponse(response) {
    if (!response.body) return null
    const reader = response.body.getReader()
    const chunks = []
    let size = 0

    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        size += value.byteLength
        if (size > MAX_SYNC_BYTES) {
          await reader.cancel()
          return null
        }
        chunks.push(value)
      }
    } finally {
      reader.releaseLock()
    }

    const bytes = new Uint8Array(size)
    let offset = 0
    chunks.forEach((chunk) => {
      bytes.set(chunk, offset)
      offset += chunk.byteLength
    })
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes)
  }

  normalizedOmarchyPayload(value) {
    if (!value || typeof value !== "object" || Array.isArray(value)) return null
    if (typeof value.name !== "string" || !THEME_NAME.test(value.name)) return null
    if (typeof value.revision !== "string" || !/^[0-9a-f]{64}$/.test(value.revision)) return null
    if (value.theme !== null && (typeof value.theme !== "string" || value.theme !== value.name ||
        !this.optionTargets.some((option) => option.dataset.themeValue === value.theme))) return null
    if (!value.colors || typeof value.colors !== "object" || Array.isArray(value.colors)) return null
    if (!COLOR_KEYS.every((key) => typeof value.colors[key] === "string" && HEX.test(value.colors[key]))) return null

    return {
      name: value.name,
      theme: value.theme,
      revision: value.revision,
      colors: Object.fromEntries(COLOR_KEYS.map((key) => [key, value.colors[key]]))
    }
  }

  applyOmarchyTheme(payload) {
    this.appliedOmarchyRevision = payload.revision
    if (!this.barTarget.hidden) this.close()
    this.renderOmarchyTheme(payload)
    this.reflect()
  }

  renderOmarchyTheme(payload) {
    if (payload.theme) {
      this.applyTheme(payload.theme)
      for (let index = 0; index < 16; index += 1) {
        const slot = String(index).padStart(2, "0")
        document.documentElement.style.setProperty(`--ansi-${slot}-slot`, payload.colors[`color${index}`])
      }
      document.documentElement.style.setProperty("--terminal-cursor", payload.colors.cursor)
      this.syncThemeColor()
    } else {
      this.applyLiveTheme(payload)
    }
  }

  applyLiveTheme(payload) {
    const colors = payload.colors
    const properties = {
      "--bg": colors.background,
      "--cell": `color-mix(in srgb, ${colors.background} 96%, ${colors.foreground})`,
      "--cell-2": `color-mix(in srgb, ${colors.background} 91%, ${colors.foreground})`,
      "--text": colors.foreground,
      "--text-soft": `color-mix(in srgb, ${colors.foreground} 84%, ${colors.background})`,
      "--text-muted": `color-mix(in srgb, ${colors.foreground} 72%, ${colors.background})`,
      "--faint": `color-mix(in srgb, ${colors.foreground} 52%, ${colors.background})`,
      "--line": `color-mix(in srgb, ${colors.foreground} 12%, transparent)`,
      "--line-strong": `color-mix(in srgb, ${colors.foreground} 22%, transparent)`,
      "--accent": colors.color4,
      "--accent-soft": `color-mix(in srgb, ${colors.color4} 13%, transparent)`,
      "--on-accent": this.contrastInk(colors.color4),
      "--success": colors.color2,
      "--warning": colors.color3,
      "--danger": colors.color1,
      "--success-soft": `color-mix(in srgb, ${colors.color2} 13%, transparent)`,
      "--warning-soft": `color-mix(in srgb, ${colors.color3} 13%, transparent)`,
      "--danger-soft": `color-mix(in srgb, ${colors.color1} 13%, transparent)`,
      "--info": colors.color4,
      "--cyan": colors.color6,
      "--magenta": colors.color5,
      "--break": colors.background,
      "--ansi-00-slot": colors.color0,
      "--ansi-01-slot": colors.color1,
      "--ansi-02-slot": colors.color2,
      "--ansi-03-slot": colors.color3,
      "--ansi-04-slot": colors.color4,
      "--ansi-05-slot": colors.color5,
      "--ansi-06-slot": colors.color6,
      "--ansi-07-slot": colors.color7,
      "--ansi-08-slot": colors.color8,
      "--ansi-09-slot": colors.color9,
      "--ansi-10-slot": colors.color10,
      "--ansi-11-slot": colors.color11,
      "--ansi-12-slot": colors.color12,
      "--ansi-13-slot": colors.color13,
      "--ansi-14-slot": colors.color14,
      "--ansi-15-slot": colors.color15,
      "--terminal-cursor": colors.cursor,
      "--accent-ink": "var(--ansi-04)",
      "--cyan-ink": "var(--ansi-06)",
      "--danger-ink": "var(--ansi-01)",
      "--search-accent-ink": "var(--ansi-04)",
      "--terminal-accent-readable": this.readableThemeColor(colors.color4, colors.background, colors.foreground),
      "--terminal-success-readable": this.readableThemeColor(colors.color2, colors.background, colors.foreground),
      "--terminal-warning-readable": this.readableThemeColor(colors.color3, colors.background, colors.foreground),
      "--terminal-muted-readable": this.readableThemeColor(colors.color7, colors.background, colors.foreground)
    }

    this.clearLivePalette()
    Object.entries(properties).forEach(([property, value]) => document.documentElement.style.setProperty(property, value))
    document.documentElement.style.colorScheme = this.relativeLuminance(colors.background) > 0.45 ? "light" : "dark"
    document.documentElement.dataset.theme = "omarchy-live"
    this.syncThemeColor()
  }

  clearLivePalette() {
    LIVE_PROPERTIES.forEach((property) => document.documentElement.style.removeProperty(property))
    document.documentElement.style.removeProperty("color-scheme")
  }

  contrastInk(color) {
    const luminance = this.relativeLuminance(color)
    const blackContrast = (luminance + 0.05) / 0.05
    const whiteContrast = 1.05 / (luminance + 0.05)
    return blackContrast >= whiteContrast ? "#000000" : "#ffffff"
  }

  readableThemeColor(color, background, foreground) {
    const contrast = (first, second) => {
      const values = [this.relativeLuminance(first), this.relativeLuminance(second)]
      return (Math.max(...values) + 0.05) / (Math.min(...values) + 0.05)
    }
    if (contrast(color, background) >= 4.5) return color

    const channels = (hex) => [1, 3, 5].map((offset) => parseInt(hex.slice(offset, offset + 2), 16))
    const source = channels(color)
    const text = channels(foreground)
    for (let weight = 0.9; weight >= 0; weight -= 0.1) {
      const mixed = source.map((value, index) => Math.round(value * weight + text[index] * (1 - weight)))
      const candidate = `#${mixed.map((value) => value.toString(16).padStart(2, "0")).join("")}`
      if (contrast(candidate, background) >= 4.5) return candidate
    }
    return foreground
  }

  relativeLuminance(color) {
    const channels = [1, 3, 5].map((offset) => parseInt(color.slice(offset, offset + 2), 16) / 255)
      .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4)
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
  }

  syncThemeColor() {
    const background = getComputedStyle(document.documentElement).getPropertyValue("--bg").trim()
    document.querySelector('meta[name="theme-color"]')?.setAttribute("content", background)
  }
}

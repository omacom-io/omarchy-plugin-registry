import { Controller } from "@hotwired/stimulus"

const GLYPHS = "░▒▓/\\<>+=*#%&@$0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const TICK_MS = 50
const HOLD_MS = 3600
const IN_TICKS = 26
const OUT_TICKS = 12

export default class extends Controller {
  static targets = ["canvas", "prefix"]
  static values = { messages: Array }

  connect() {
    if (!this.messagesValue.length) return

    this.index = 0
    this.visible = true
    this.running = false
    this.paused = false
    this.resumeFrame = null
    this.showPrompt = true
    this.modeQuery = window.matchMedia("(prefers-reduced-motion: reduce), (max-width: 760px), (hover: none) and (pointer: coarse)")
    this.staticMode = this.modeQuery.matches

    this.onResize = () => this.refreshMode()
    window.addEventListener("resize", this.onResize)
    this.onModeChange = () => this.refreshMode()
    this.modeQuery.addEventListener("change", this.onModeChange)

    this.onVisibility = () => this.syncRunning()
    document.addEventListener("visibilitychange", this.onVisibility)

    this.beforeCache = () => { this.cancelResume(); this.halt() }
    document.addEventListener("turbo:before-cache", this.beforeCache)

    this.observer = new IntersectionObserver((entries) => {
      this.visible = entries[0]?.isIntersecting ?? true
      this.syncRunning()
    })
    this.observer.observe(this.element)

    this.themeWatch = new MutationObserver(() => { this.readColors(); this.paintStatic() })
    this.themeWatch.observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme"] })

    this.setup()
    this.readColors()
    if (this.staticMode) this.paintFirstMessage()
    else this.startMessage()
  }

  disconnect() {
    this.cancelResume()
    this.halt()
    window.removeEventListener("resize", this.onResize)
    this.modeQuery?.removeEventListener("change", this.onModeChange)
    document.removeEventListener("visibilitychange", this.onVisibility)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.observer?.disconnect()
    this.themeWatch?.disconnect()
  }

  refreshMode() {
    const nextStaticMode = this.modeQuery.matches
    const changed = nextStaticMode !== this.staticMode
    if (changed) {
      this.cancelResume()
      this.halt()
      this.staticMode = nextStaticMode
      this.paused = !nextStaticMode && (this.element.matches(":hover") || this.element.matches(":focus-within"))
    }

    this.setup()
    this.readColors()
    if (this.staticMode) {
      this.paintFirstMessage()
    } else if (changed) {
      this.index = 0
      this.startMessage()
      if (this.paused) this.paintStatic()
    } else {
      this.paintStatic()
    }
  }

  paintFirstMessage() {
    this.index = 0
    this.showPrompt = true
    if (this.hasPrefixTarget) this.prefixTarget.hidden = false
    this.setup()
    this.setChars(this.messagesValue[0])
    this.paintStatic()
  }

  setup() {
    const canvas = this.canvasTarget
    const rect = canvas.parentElement.getBoundingClientRect()
    const dpr = Math.min(window.devicePixelRatio || 1, 2)
    this.cssWidth = rect.width
    this.cssHeight = rect.height
    canvas.width = Math.round(rect.width * dpr)
    canvas.height = Math.round(rect.height * dpr)
    this.ctx = canvas.getContext("2d")
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
    this.ctx.font = "700 12.5px 'JetBrains Mono', monospace"
    this.ctx.textBaseline = "middle"
    this.cell = Math.ceil(this.ctx.measureText("M").width)
  }

  readColors() {
    this.colors = {
      bg: getComputedStyle(this.element.closest(".promptline") || this.element).backgroundColor,
      text: this.resolvedColor("--ansi-07-ink"),
      faint: this.resolvedColor("--faint"),
      accent: this.resolvedColor("--accent"),
      ansi02: this.resolvedColor("--ansi-02-ink")
    }
  }

  resolvedColor(property) {
    const probe = document.createElement("span")
    probe.style.color = `var(${property})`
    probe.hidden = true
    this.element.append(probe)
    const color = getComputedStyle(probe).color
    probe.remove()
    return color
  }

  fit(chars) {
    const room = Math.floor((this.cssWidth - 4) / this.cell)
    return chars.length > room ? chars.slice(0, Math.max(0, room)) : chars
  }

  startMessage() {
    this.showPrompt = this.index === 0
    if (this.hasPrefixTarget && this.prefixTarget.hidden === this.showPrompt) {
      this.prefixTarget.hidden = !this.showPrompt
      this.setup()
    }
    this.setChars(this.messagesValue[this.index])
    this.reveal = this.chars.map(() => Math.ceil(Math.random() * IN_TICKS))
    this.tick = 0
    this.phase = "in"
    this.paint()
    this.syncRunning()
  }

  pause() {
    if (this.staticMode) return
    this.cancelResume()
    this.paused = true
    this.halt()
  }

  resume() {
    if (this.staticMode) return
    this.cancelResume()
    this.resumeFrame = requestAnimationFrame(() => {
      this.resumeFrame = null
      if (!this.element.isConnected || this.element.matches(":hover") || this.element.matches(":focus-within")) return
      this.paused = false
      if (this.phase === "idle") this.scheduleNextMessage()
      else this.syncRunning()
    })
  }

  cancelResume() {
    if (this.resumeFrame) cancelAnimationFrame(this.resumeFrame)
    this.resumeFrame = null
  }

  scheduleNextMessage() {
    if (this.paused) return
    this.hold = setTimeout(() => {
      this.hold = null
      this.phase = "out"
      this.tick = 0
      this.syncRunning()
    }, HOLD_MS)
  }

  syncRunning() {
    const shouldRun = !this.staticMode && !this.paused && this.visible && !document.hidden && this.phase !== "idle"
    if (shouldRun && !this.running) {
      this.running = true
      this.last = performance.now()
      this.acc = 0
      this.frame = requestAnimationFrame((now) => this.loop(now))
    } else if (!shouldRun && this.running) {
      this.halt()
    }
  }

  loop(now) {
    if (!this.running) return
    this.acc = Math.min(this.acc + (now - this.last), TICK_MS * 2)
    this.last = now
    if (this.acc >= TICK_MS) {
      this.acc -= TICK_MS
      this.step()
    }
    if (this.running) this.frame = requestAnimationFrame((next) => this.loop(next))
  }

  halt() {
    this.running = false
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.hold) clearTimeout(this.hold)
    this.frame = null
    this.hold = null
  }

  step() {
    this.tick += 1
    if (this.phase === "in" && this.tick > IN_TICKS) {
      this.phase = "idle"
      this.halt()
      this.paintStatic()
      this.scheduleNextMessage()
      return
    }
    if (this.phase === "out" && this.tick > OUT_TICKS) {
      this.index = (this.index + 1) % this.messagesValue.length
      this.startMessage()
      return
    }
    this.paint()
  }

  originX() {
    if (this.showPrompt) return 0
    return Math.max(0, Math.round((this.cssWidth - this.chars.length * this.cell) / 2))
  }

  setChars(message) {
    this.chars = this.fit(Array.from(message))
    this.numberPositions = new Set()
    const text = this.chars.join("")
    for (const match of text.matchAll(/\d[\d,.]*[kmb]?/gi)) {
      for (let offset = 0; offset < match[0].length; offset += 1) {
        this.numberPositions.add(match.index + offset)
      }
    }
  }

  settledColor(position) {
    return this.numberPositions.has(position) ? this.colors.ansi02 : this.colors.text
  }

  paint() {
    const { ctx, chars, cell } = this
    ctx.fillStyle = this.colors.bg
    ctx.fillRect(0, 0, this.cssWidth, this.cssHeight)
    const x0 = this.originX()
    const y = this.cssHeight / 2 + 1
    chars.forEach((char, position) => {
      let glyph = char
      const settled = this.phase === "in" ? this.tick >= this.reveal[position] : this.tick <= this.reveal[position] - OUT_TICKS / 2
      let color = this.settledColor(position)
      if (!settled && char !== " ") {
        glyph = GLYPHS[Math.floor(Math.random() * GLYPHS.length)]
        color = this.numberPositions.has(position)
          ? this.colors.ansi02
          : (Math.random() < 0.24 ? this.colors.accent : this.colors.faint)
      }
      ctx.fillStyle = color
      ctx.fillText(glyph, x0 + position * cell, y)
    })
  }

  paintStatic() {
    if (!this.chars) return
    const { ctx, chars, cell } = this
    ctx.fillStyle = this.colors.bg
    ctx.fillRect(0, 0, this.cssWidth, this.cssHeight)
    const x0 = this.originX()
    const y = this.cssHeight / 2 + 1
    chars.forEach((char, position) => {
      ctx.fillStyle = this.settledColor(position)
      ctx.fillText(char, x0 + position * cell, y)
    })
  }
}

import { Controller } from "@hotwired/stimulus"

const SLOTS = 10
const TICK_MS = 80
const STAGGER_MS = 480
const START_DELAY_MS = 1600
const REPLAY_DELAY_MS = 250
const REPLAY_EVERY_MS = 45000
const DURATION_MS = TICK_MS * Math.ceil(SLOTS * 1.6)

function compact(input) {
  if (input < 1000) return String(input)
  const units = [[1e9, "B"], [1e6, "M"], [1e3, "k"]]
  for (const [divisor, unit] of units) {
    if (input >= divisor) return parseFloat((input / divisor).toPrecision(3)).toString() + unit
  }
  return String(input)
}

export default class extends Controller {
  static targets = ["stat"]

  connect() {
    this.rows = this.statTargets.map((stat, index) => ({
      bar: stat.querySelector("[data-pacman-bar]"),
      num: stat.querySelector("[data-pacman-num]"),
      value: parseInt(stat.dataset.value, 10) || 0,
      offset: index * STAGGER_MS,
      lastTick: -1
    })).filter((row) => row.bar && row.num)
    if (!this.rows.length) return

    this.frame = null
    this.replayTimer = null
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce), (max-width: 760px)")
    this.onMotionChange = () => this.syncMotionMode()
    this.motionQuery.addEventListener("change", this.onMotionChange)

    this.onPageshow = (event) => {
      if (!event.persisted) return
      if (this.motionQuery.matches) {
        this.stop()
        this.finalize()
      } else {
        this.restart(START_DELAY_MS)
      }
    }
    window.addEventListener("pageshow", this.onPageshow)

    this.beforeCache = () => {
      this.stop()
      this.finalize()
    }
    document.addEventListener("turbo:before-cache", this.beforeCache)

    this.syncMotionMode()
  }

  disconnect() {
    if (!this.rows?.length) return
    this.motionQuery?.removeEventListener("change", this.onMotionChange)
    window.removeEventListener("pageshow", this.onPageshow)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    this.stop()
  }

  syncMotionMode() {
    if (this.motionQuery.matches) {
      this.stop()
      this.finalize()
    } else {
      this.restart(START_DELAY_MS)
    }
  }

  replay() {
    if (this.motionQuery?.matches || this.frame) return
    this.restart(REPLAY_DELAY_MS)
  }

  restart(delay) {
    if (this.motionQuery?.matches) return
    this.stop()
    this.delay = delay
    this.acc = 0
    this.last = null
    this.rows.forEach((row) => { row.lastTick = -1 })
    this.frame = requestAnimationFrame((now) => this.loop(now))
  }

  stop() {
    if (this.frame) cancelAnimationFrame(this.frame)
    if (this.replayTimer) clearTimeout(this.replayTimer)
    this.frame = null
    this.replayTimer = null
  }

  loop(now) {
    if (this.last !== null) this.acc += Math.min(now - this.last, 250)
    this.last = now
    let done = true
    this.rows.forEach((row) => {
      const local = this.acc - this.delay - row.offset
      if (local < 0) { done = false; return }
      const tick = Math.floor(local / TICK_MS)
      const progress = Math.min(local / DURATION_MS, 1)
      if (progress < 1) done = false
      if (tick === row.lastTick) return
      row.lastTick = tick
      this.paint(row, progress, tick)
    })
    if (done) {
      this.frame = null
      this.replayTimer = setTimeout(() => this.restart(REPLAY_DELAY_MS), REPLAY_EVERY_MS)
    } else {
      this.frame = requestAnimationFrame((next) => this.loop(next))
    }
  }

  paint(row, progress, tick) {
    const mouth = Math.floor(progress * SLOTS)
    if (progress >= 1) {
      row.bar.textContent = "[" + "-".repeat(SLOTS) + "]"
    } else {
      let rest = ""
      for (let slot = mouth + 1; slot < SLOTS; slot += 1) rest += slot % 2 === 0 ? "o" : " "
      row.bar.innerHTML = "[" + "-".repeat(mouth) + "<i>" + (tick % 2 === 0 ? "C" : "c") + "</i>" + rest + "]"
    }
    row.num.textContent = compact(Math.round(row.value * progress))
  }

  finalize() {
    this.rows.forEach((row) => {
      row.bar.textContent = "[" + "-".repeat(SLOTS) + "]"
      row.num.textContent = compact(row.value)
      row.lastTick = -1
    })
  }
}

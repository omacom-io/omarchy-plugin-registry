import { Controller } from "@hotwired/stimulus"

const VIEWBOX_WIDTH = 4131
const VIEWBOX_HEIGHT = 950
const FIRST_TILE_DELAY_MS = 560
const TILE_STAGGER_MS = 1250
const FIRST_FETCH_PART_DELAY_MS = 2650
const FETCH_PART_STAGGER_MS = 90
const COMPLETE_AFTER_MS = 3650

export default class extends Controller {
  connect() {
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.onMotionChange = (event) => { if (event.matches) this.finish() }
    this.onPageShow = (event) => { if (event.persisted) this.finish() }
    this.beforeCache = () => this.finish()

    this.motionQuery.addEventListener("change", this.onMotionChange)
    window.addEventListener("pageshow", this.onPageShow)
    document.addEventListener("turbo:before-cache", this.beforeCache)

    if (this.element.classList.contains("is-complete") || this.motionQuery.matches) {
      this.finish()
      return
    }

    this.setWordmarkDelays()
    this.setFetchDelays()
    this.completeTimer = window.setTimeout(() => this.finish(), COMPLETE_AFTER_MS)
  }

  disconnect() {
    window.clearTimeout(this.completeTimer)
    this.motionQuery?.removeEventListener("change", this.onMotionChange)
    window.removeEventListener("pageshow", this.onPageShow)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  finish() {
    window.clearTimeout(this.completeTimer)
    this.completeTimer = null
    this.element.classList.add("is-complete")
  }

  setWordmarkDelays() {
    const tiles = [...this.element.querySelectorAll(".hero__wm rect")]
    const distances = tiles.map((tile) => {
      const x = Number(tile.getAttribute("x"))
      const y = Number(tile.getAttribute("y"))
      const width = Number(tile.getAttribute("width"))
      const height = Number(tile.getAttribute("height"))
      if (![x, y, width, height].every(Number.isFinite)) return 0

      const centerX = x + width / 2
      const centerY = y + height / 2
      return VIEWBOX_HEIGHT - centerY + Math.abs(centerX - VIEWBOX_WIDTH / 2) * 0.5
    })
    const maximum = Math.max(1, ...distances)

    tiles.forEach((tile, index) => {
      const delay = Math.round(FIRST_TILE_DELAY_MS + distances[index] / maximum * TILE_STAGGER_MS)
      tile.style.setProperty("--hero-reveal-delay", `${delay}ms`)
    })
  }

  setFetchDelays() {
    this.element.querySelectorAll(".fetch__mark, .fetch__metric, .fetch__row, .fetch__prompt")
      .forEach((part, index) => {
        part.style.setProperty("--hero-part-delay", `${FIRST_FETCH_PART_DELAY_MS + index * FETCH_PART_STAGGER_MS}ms`)
      })
  }
}

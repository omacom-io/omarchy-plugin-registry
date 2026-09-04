import { Controller } from "@hotwired/stimulus"

// Adds a small perspective response to signal cards. Navigation remains a
// normal link; this is visual enhancement only and never runs for touch or
// reduced-motion users.
export default class extends Controller {
  connect() {
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.pointerQuery = window.matchMedia("(pointer: coarse)")
    this.beforeCache = () => this.reset()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  move(event) {
    if (this.motionQuery.matches || this.pointerQuery.matches) return

    const bounds = this.element.getBoundingClientRect()
    const x = (event.clientX - bounds.left) / bounds.width
    const y = (event.clientY - bounds.top) / bounds.height

    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      this.element.style.setProperty("--card-tilt-x", `${((0.5 - y) * 3).toFixed(2)}deg`)
      this.element.style.setProperty("--card-tilt-y", `${((x - 0.5) * 3).toFixed(2)}deg`)
    })
  }

  reset() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    this.element.style.removeProperty("--card-tilt-x")
    this.element.style.removeProperty("--card-tilt-y")
  }
}

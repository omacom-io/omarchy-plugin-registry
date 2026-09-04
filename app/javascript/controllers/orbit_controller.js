import { Controller } from "@hotwired/stimulus"

// A restrained pointer response for the decorative registry orbit. The rings
// keep their own CSS rotation; this controller only nudges the stage and the
// dotted cursor field. Coarse pointers and reduced-motion users get the same
// artwork without the movement.
export default class extends Controller {
  static targets = ["stage", "cursor"]

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

    const bounds = this.stageTarget.getBoundingClientRect()
    const x = (event.clientX - bounds.left) / bounds.width
    const y = (event.clientY - bounds.top) / bounds.height

    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = requestAnimationFrame(() => {
      this.stageTarget.style.setProperty("--orbit-tilt-x", `${((0.5 - y) * 5).toFixed(2)}deg`)
      this.stageTarget.style.setProperty("--orbit-tilt-y", `${((x - 0.5) * 5).toFixed(2)}deg`)
      this.cursorTarget.style.setProperty("--orbit-cursor-x", `${(x * bounds.width).toFixed(2)}px`)
      this.cursorTarget.style.setProperty("--orbit-cursor-y", `${(y * bounds.height).toFixed(2)}px`)
      this.element.classList.add("registry-orbit--active")
    })
  }

  reset() {
    if (this.frame) cancelAnimationFrame(this.frame)
    this.frame = null
    this.stageTarget.style.removeProperty("--orbit-tilt-x")
    this.stageTarget.style.removeProperty("--orbit-tilt-y")
    this.cursorTarget.style.removeProperty("--orbit-cursor-x")
    this.cursorTarget.style.removeProperty("--orbit-cursor-y")
    this.element.classList.remove("registry-orbit--active")
  }
}

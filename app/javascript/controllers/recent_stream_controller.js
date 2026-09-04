import { Controller } from "@hotwired/stimulus"

const POINTER_RETURN_KEY = "registry-discovery-pointer-return"
const POINTER_POSITION_KEY = "registry-discovery-pointer-position"

export default class extends Controller {
  static targets = ["toggle"]

  connect() {
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.onMotionChange = () => this.syncMotion()
    this.beforeCache = () => this.reset()
    this.onPageShow = () => this.resumeAfterPointerReturn()
    this.onPointerEnter = () => {
      this.element.classList.add("is-hover-paused")
      if (this.recoveryReady && !this.hoveredAtRestore) this.returnInteracted = true
    }
    this.onPointerLeave = () => this.element.classList.remove("is-hover-paused")
    this.onPointerInteraction = () => {
      if (this.recoveryReady) this.returnInteracted = true
    }
    this.onFocusIn = (event) => {
      if (this.recoveryReady && event.target !== this.restoredFocus) this.returnInteracted = true
    }
    this.onKeydown = () => {
      if (this.recoveryReady) this.returnInteracted = true
    }
    this.motionQuery.addEventListener("change", this.onMotionChange)
    this.element.addEventListener("pointerenter", this.onPointerEnter)
    this.element.addEventListener("pointerleave", this.onPointerLeave)
    this.element.addEventListener("pointermove", this.onPointerInteraction)
    this.element.addEventListener("pointerdown", this.onPointerInteraction)
    this.element.addEventListener("focusin", this.onFocusIn)
    document.addEventListener("keydown", this.onKeydown, true)
    window.addEventListener("pageshow", this.onPageShow)
    document.addEventListener("turbo:load", this.onPageShow)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.element.classList.add("is-enhanced")
    this.syncMotion()
    this.resumeAfterPointerReturn()
  }

  disconnect() {
    this.motionQuery?.removeEventListener("change", this.onMotionChange)
    this.element.removeEventListener("pointerenter", this.onPointerEnter)
    this.element.removeEventListener("pointerleave", this.onPointerLeave)
    this.element.removeEventListener("pointermove", this.onPointerInteraction)
    this.element.removeEventListener("pointerdown", this.onPointerInteraction)
    this.element.removeEventListener("focusin", this.onFocusIn)
    document.removeEventListener("keydown", this.onKeydown, true)
    window.removeEventListener("pageshow", this.onPageShow)
    document.removeEventListener("turbo:load", this.onPageShow)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    window.clearTimeout(this.returnTimer)
    this.reset()
  }

  resumeAfterPointerReturn() {
    let returning = false
    try {
      returning = window.sessionStorage.getItem(POINTER_RETURN_KEY) === "true"
    } catch {
    }
    if (!returning) return

    this.element.classList.remove("is-hover-paused")
    if (!this.element.classList.contains("is-pointer-return")) this.returnInteracted = false
    this.element.classList.add("is-pointer-return")
    const rect = this.element.getBoundingClientRect()
    let restoredPointerInside = false
    try {
      const coordinates = window.sessionStorage.getItem(POINTER_POSITION_KEY)?.split(",").map(Number)
      restoredPointerInside = coordinates?.length === 2 && coordinates.every(Number.isFinite) &&
        coordinates[0] >= rect.left && coordinates[0] <= rect.right &&
        coordinates[1] >= rect.top && coordinates[1] <= rect.bottom
    } catch {
    }
    this.hoveredAtRestore = this.element.matches(":hover") || restoredPointerInside
    const active = document.activeElement
    this.restoredFocus = this.element.contains(active) ? active : null
    this.recoveryReady = true
    window.clearTimeout(this.returnTimer)
    this.returnTimer = window.setTimeout(() => {
      if (!this.returnInteracted && document.activeElement === this.restoredFocus &&
          this.restoredFocus?.matches(".recent-stream__open")) this.restoredFocus.blur()
      this.element.classList.remove("is-pointer-return")
      if (!this.returnInteracted) this.element.classList.remove("is-hover-paused")
      this.recoveryReady = false
      try {
        window.sessionStorage.removeItem(POINTER_RETURN_KEY)
        window.sessionStorage.removeItem(POINTER_POSITION_KEY)
      } catch {
      }
    }, 250)
  }

  toggle() {
    if (this.motionQuery.matches) return
    const paused = this.element.classList.toggle("is-paused")
    this.toggleTarget.setAttribute("aria-pressed", String(paused))
    this.toggleTarget.setAttribute("aria-label", paused ? "Resume Recently Added" : "Pause Recently Added")
    this.renderToggle(paused)
  }

  syncMotion() {
    const reduced = this.motionQuery.matches
    this.element.classList.toggle("is-reduced", reduced)
    this.element.classList.remove("is-paused")
    this.toggleTarget.hidden = reduced
    this.toggleTarget.setAttribute("aria-pressed", "false")
    this.toggleTarget.setAttribute("aria-label", "Pause Recently Added")
    this.renderToggle(false)
  }

  renderToggle(paused) {
    const symbol = document.createElement("span")
    symbol.className = "recent-stream__toggle-symbol"
    symbol.setAttribute("aria-hidden", "true")
    symbol.textContent = paused ? "→" : "‖"
    this.toggleTarget.replaceChildren(document.createTextNode(paused ? "resume " : "pause "), symbol)
  }

  reset() {
    this.element.classList.remove("is-enhanced", "is-paused", "is-reduced", "is-hover-paused", "is-pointer-return")
    this.toggleTarget.hidden = true
    this.toggleTarget.setAttribute("aria-pressed", "false")
  }
}

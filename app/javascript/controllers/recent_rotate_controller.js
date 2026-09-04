import { Controller } from "@hotwired/stimulus"

const MOVE_MS = 420
const EASE = "cubic-bezier(0.33, 1, 0.68, 1)"

export default class extends Controller {
  static targets = ["row", "stack", "card", "status"]
  static values = { label: { type: String, default: "Most Wanted" } }

  connect() {
    this.motionQuery = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.reducedMotion = this.motionQuery.matches

    this.onMotionChange = (event) => {
      this.reducedMotion = event.matches
      this.cancelAnimations()
    }
    this.motionQuery.addEventListener("change", this.onMotionChange)

    this.beforeCache = () => this.cancelAnimations()
    document.addEventListener("turbo:before-cache", this.beforeCache)
  }

  disconnect() {
    this.cancelAnimations()
    this.motionQuery?.removeEventListener("change", this.onMotionChange)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  previous(event) {
    event?.preventDefault()
    this.rotate(-1)
  }

  next(event) {
    event?.preventDefault()
    this.rotate(1)
  }

  keydown(event) {
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
    if (event.target.closest("input, textarea, select, [contenteditable]")) return
    if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.rotate(-1)
    } else if (event.key === "ArrowRight") {
      event.preventDefault()
      this.rotate(1)
    }
  }

  rotate(direction = 1) {
    if (!this.hasStackTarget || this.cardTargets.length < 2) return

    const master = this.rowTarget.querySelector(".recent-card--master")
    const candidate = direction > 0 ? this.stackTarget.firstElementChild : this.stackTarget.lastElementChild
    if (!master || !candidate) return

    const cards = this.cardTargets
    this.cancelAnimations()
    const before = this.reducedMotion ? null : new Map(cards.map((card) => [card, card.getBoundingClientRect()]))
    cards.forEach((card) => { card.style.animation = "none" })

    master.classList.remove("recent-card--master")
    candidate.classList.add("recent-card--master")
    this.rowTarget.insertBefore(candidate, this.stackTarget)
    if (direction > 0) this.stackTarget.append(master)
    else this.stackTarget.insertBefore(master, this.stackTarget.firstElementChild)

    if (before) {
      cards.forEach((card) => {
        const from = before.get(card)
        const to = card.getBoundingClientRect()
        const dx = from.left - to.left
        const dy = from.top - to.top
        const sx = to.width ? from.width / to.width : 1
        const sy = to.height ? from.height / to.height : 1
        if (Math.abs(dx) < 1 && Math.abs(dy) < 1 && Math.abs(sx - 1) < 0.01 && Math.abs(sy - 1) < 0.01) return
        card.style.transformOrigin = "top left"
        card.animate(
          [{ transform: `translate(${dx}px, ${dy}px) scale(${sx}, ${sy})` }, { transform: "none" }],
          { duration: MOVE_MS, easing: EASE }
        )
      })
    }

    if (this.hasStatusTarget) {
      const name = candidate.querySelector(".recent-card__name")?.textContent.trim() || "plugin"
      this.statusTarget.textContent = `Showing ${this.labelValue} plugin ${name}`
    }
  }

  cancelAnimations() {
    this.cardTargets.forEach((card) => card.getAnimations().forEach((animation) => animation.cancel()))
  }
}

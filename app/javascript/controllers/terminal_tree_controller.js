import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["link"]
  static values = { activateLastAtBottom: Boolean }

  connect() {
    this.sections = this.linkTargets.map((link) => {
      const id = decodeURIComponent(link.hash.slice(1))
      return document.getElementById(id)
    })
    this.currentIndex = Math.max(0, this.linkTargets.findIndex((link) => link.classList.contains("is-active")))
    this.preferredIndex = this.linkTargets.findIndex((link) => link.hash === window.location.hash)
    this.preferredUntil = this.preferredIndex >= 0 ? performance.now() + 120 : 0
    this.frame = null
    this.onScroll = () => this.scheduleUpdate()
    this.onHashChange = () => {
      const index = this.linkTargets.findIndex((link) => link.hash === window.location.hash)
      if (index >= 0) {
        this.preferredIndex = index
        this.preferredUntil = performance.now() + 120
      }
      this.scheduleUpdate()
    }

    window.addEventListener("scroll", this.onScroll, { passive: true })
    window.addEventListener("resize", this.onScroll)
    window.addEventListener("hashchange", this.onHashChange)
    this.element.classList.add("is-enhanced")
    this.scheduleUpdate()
  }

  disconnect() {
    window.removeEventListener("scroll", this.onScroll)
    window.removeEventListener("resize", this.onScroll)
    window.removeEventListener("hashchange", this.onHashChange)
    if (this.frame) cancelAnimationFrame(this.frame)
  }

  select(event) {
    const index = this.linkTargets.indexOf(event.currentTarget)
    if (index < 0) return
    this.preferredIndex = index
    this.preferredUntil = performance.now() + 120
    this.activate(index)
  }

  scheduleUpdate() {
    if (this.frame) return
    this.frame = requestAnimationFrame(() => {
      this.frame = null
      this.update()
    })
  }

  update() {
    const available = this.sections
      .map((section, index) => ({ section, index }))
      .filter(({ section }) => section)
    if (!available.length) return

    const marker = Math.min(120, Math.max(72, window.innerHeight * 0.12))
    const crossed = available
      .map(({ section, index }) => ({ index, top: section.getBoundingClientRect().top }))
      .filter(({ top }) => top <= marker)
    let activeIndex = available[0].index
    if (crossed.length) activeIndex = this.pickAtFurthestTop(crossed)

    const preferred = this.sections[this.preferredIndex]
    if (preferred) {
      const bounds = preferred.getBoundingClientRect()
      const replacement = available
        .map(({ section, index }) => ({ index, bounds: section.getBoundingClientRect() }))
        .find(({ index, bounds: candidate }) => index > this.preferredIndex && candidate.bottom > 0 &&
          candidate.top > bounds.top + 1 && candidate.top <= window.innerHeight * 0.35)
      const preferenceSettling = performance.now() < this.preferredUntil
      const movedToAnotherSection = !preferenceSettling && (replacement || activeIndex > this.preferredIndex ||
        (activeIndex < this.preferredIndex && bounds.top >= window.innerHeight * 0.8))
      if (movedToAnotherSection) {
        if (replacement) activeIndex = replacement.index
        this.preferredIndex = -1
      } else if (bounds.bottom > 0 && bounds.top < window.innerHeight * 0.8) {
        activeIndex = this.preferredIndex
      }
    }

    if (this.activateLastAtBottomValue &&
        window.scrollY + window.innerHeight >= document.documentElement.scrollHeight - 2) {
      activeIndex = available[available.length - 1].index
    }
    this.activate(activeIndex)
  }

  pickAtFurthestTop(positions) {
    const furthest = Math.max(...positions.map(({ top }) => top))
    const tied = positions.filter(({ top }) => Math.abs(top - furthest) <= 1)
    return tied.find(({ index }) => index === this.preferredIndex)?.index ?? tied[0].index
  }

  activate(index) {
    this.currentIndex = index
    this.linkTargets.forEach((link, position) => {
      const active = position === index
      link.classList.toggle("is-active", active)
      link.classList.toggle("is-passed", position < index)
      if (active) link.setAttribute("aria-current", "location")
      else link.removeAttribute("aria-current")
    })
  }
}

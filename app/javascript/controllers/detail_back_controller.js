import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "registry-browse-return"

export default class extends Controller {
  static values = { fallbackUrl: String }

  connect() {
    this.resetNavigation = this.resetNavigation.bind(this)
    this.resetNavigation()
    window.addEventListener("pageshow", this.resetNavigation)
    document.addEventListener("turbo:load", this.resetNavigation)
  }

  disconnect() {
    window.removeEventListener("pageshow", this.resetNavigation)
    document.removeEventListener("turbo:load", this.resetNavigation)
  }

  resetNavigation() {
    this.navigating = false
  }

  back(event) {
    if (event.defaultPrevented || event.key !== "Backspace" || event.isComposing || event.altKey || event.ctrlKey ||
        event.metaKey || event.shiftKey) return
    if (document.querySelector("dialog[open], .theme-picker:not([hidden])") || this.editableTarget(event.target)) return

    event.preventDefault()
    if (this.navigating) return

    this.navigating = true
    window.location.assign(this.returnUrl())
  }

  editableTarget(target) {
    if (!(target instanceof Element)) return false
    return Boolean(target.closest("input, textarea, select, [contenteditable]:not([contenteditable='false'])"))
  }

  returnUrl() {
    const fallback = new URL(this.fallbackUrlValue, window.location.origin)

    try {
      const stored = new URL(window.sessionStorage.getItem(STORAGE_KEY))
      if (stored.origin === window.location.origin && stored.pathname === fallback.pathname) {
        stored.hash = fallback.hash
        return stored.href
      }
    } catch {
      // Invalid or unavailable session storage falls back to Browse.
    }

    return fallback.href
  }
}

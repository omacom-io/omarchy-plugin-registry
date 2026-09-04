import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["front", "back", "toggle"]

  connect() {
    this.beforeCache = () => this.flip(false)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.flip(false)
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
  }

  toggle(event) {
    if (event.target.closest("a, button")) return
    this.flip(!this.element.classList.contains("is-flipped"))
  }

  toggleButton() {
    const state = !this.element.classList.contains("is-flipped")
    this.flip(state)
    if (state) this.backTarget.querySelector("a, button")?.focus({ preventScroll: true })
    else this.toggleTarget.focus({ preventScroll: true })
  }

  keydown(event) {
    if (event.key !== "Escape" || !this.element.classList.contains("is-flipped")) return
    event.preventDefault()
    this.flip(false)
    this.toggleTarget.focus({ preventScroll: true })
  }

  flip(state) {
    this.element.classList.toggle("is-flipped", state)
    this.toggleTarget.setAttribute("aria-expanded", state)
    this.frontTarget.toggleAttribute("inert", state)
    this.frontTarget.setAttribute("aria-hidden", state)
    this.backTarget.toggleAttribute("inert", !state)
    this.backTarget.setAttribute("aria-hidden", !state)
  }
}

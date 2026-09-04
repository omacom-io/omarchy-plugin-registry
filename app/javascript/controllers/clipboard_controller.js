import { Controller } from "@hotwired/stimulus"
import { copyText } from "lib/clipboard"

// One-click copy for install commands and one-time secrets. The exact text
// travels in a value (never scraped from the DOM, so prompts and truncation
// can't corrupt it); the button confirms inline and reverts.
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  disconnect() {
    clearTimeout(this.timer)
    if (this.hasButtonTarget) this.reset()
  }

  async copy() {
    await copyText(this.textValue)
    this.confirm()
  }

  confirm() {
    this.buttonTarget.classList.add("copy-button--done")
    this.buttonTarget.setAttribute("aria-label", this.buttonTarget.dataset.copyCopiedLabel || "Copied")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.reset(), 1600)
  }

  reset() {
    this.buttonTarget.classList.remove("copy-button--done")
    const label = this.buttonTarget.dataset.copyDefaultLabel || "Copy"
    this.buttonTarget.setAttribute("aria-label", label)
  }
}

import { Controller } from "@hotwired/stimulus"

// Ctrl+K (or Cmd+K) jumps to the directory search box from anywhere on the
// page; Escape blurs it again.
export default class extends Controller {
  static targets = ["input"]

  connect() {
    this.shortcut = (event) => {
      const typing = /^(input|textarea|select)$/i.test(event.target.tagName) || event.target.isContentEditable
      const ctrlK = (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k"
      const slash = event.key === "/" && !event.ctrlKey && !event.metaKey && !event.altKey && !typing
      if (ctrlK || slash) {
        event.preventDefault()
        this.inputTarget.focus()
        this.inputTarget.select()
      }
    }
    document.addEventListener("keydown", this.shortcut)
  }

  disconnect() {
    document.removeEventListener("keydown", this.shortcut)
  }

  focus(event) {
    if (event.target.closest("a, button, input")) return
    this.inputTarget.focus()
    const end = this.inputTarget.value.length
    this.inputTarget.setSelectionRange(end, end)
  }
}

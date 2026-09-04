import { Controller } from "@hotwired/stimulus"

const PICKER_MAX_HEIGHT = 240
const OPTION_HEIGHT = 38
const PICKER_CHROME = 7
const VIEWPORT_GAP = 12

export default class extends Controller {
  open(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    this.ensureSpace(event.currentTarget)
  }

  prepare(event) {
    if (![" ", "Enter", "F4", "ArrowDown"].includes(event.key)) return
    if (event.key === "ArrowDown" && !event.altKey) return
    this.ensureSpace(event.currentTarget)
  }

  ensureSpace(select) {
    const rect = select.getBoundingClientRect()
    const pickerHeight = Math.min(PICKER_MAX_HEIGHT, select.options.length * OPTION_HEIGHT) + PICKER_CHROME
    const available = window.innerHeight - rect.bottom - VIEWPORT_GAP
    if (available < pickerHeight) window.scrollBy(0, pickerHeight - available)
  }
}

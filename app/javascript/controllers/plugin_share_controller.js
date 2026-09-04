import { Controller } from "@hotwired/stimulus"
import { copyText } from "lib/clipboard"
import {
  beginClipboardOperation, clipboardOperationIsCurrent, invalidateClipboardOperation
} from "lib/clipboard_feedback"

const NOTICE_MS = 2400
const POINTER_RETURN_KEY = "registry-discovery-pointer-return"
const POINTER_POSITION_KEY = "registry-discovery-pointer-position"

export default class extends Controller {
  static targets = ["status"]

  connect() {
    this.beforeCache = () => this.element.classList.remove("is-pointer-interaction")
    document.addEventListener("turbo:before-cache", this.beforeCache)
    this.element.querySelectorAll("[data-share-label]").forEach((link) => {
      link.setAttribute("aria-label", link.dataset.shareLabel)
    })
  }

  disconnect() {
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    invalidateClipboardOperation(this.pendingGeneration)
    window.clearTimeout(this.noticeTimer)
    window.clearTimeout(this.pointerTimer)
    this.element.classList.remove("is-pointer-interaction")
  }

  pointerInteraction(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return false
    this.element.classList.add("is-pointer-interaction")
    window.clearTimeout(this.pointerTimer)
    this.pointerTimer = window.setTimeout(() => this.element.classList.remove("is-pointer-interaction"), 300)
    return true
  }

  departByPointer(event) {
    if (!this.pointerInteraction(event)) return
    try {
      window.sessionStorage.setItem(POINTER_RETURN_KEY, "true")
      window.sessionStorage.setItem(POINTER_POSITION_KEY, `${event.clientX},${event.clientY}`)
    } catch {
    }
  }

  async copy(event) {
    if (event.type === "click" && (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return
    if (event.type === "keydown" && (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return

    event.preventDefault()
    event.stopPropagation()
    const generation = beginClipboardOperation()
    this.pendingGeneration = generation
    const source = event.currentTarget

    let message
    try {
      const url = new URL(source.dataset.shareUrl || source.getAttribute("href"), window.location.origin)
      if (url.origin !== window.location.origin) throw new Error("Invalid plugin URL")
      await copyText(url.href)
      message = "Plugin link copied"
    } catch {
      message = "Could not copy plugin link."
    }

    if (!clipboardOperationIsCurrent(generation) || !source.isConnected || !this.hasStatusTarget) return
    this.showStatus(message)
  }

  showStatus(message) {
    window.clearTimeout(this.noticeTimer)
    this.statusTarget.textContent = message
    this.statusTarget.hidden = false
    this.statusTarget.classList.remove("is-visible")
    void this.statusTarget.offsetWidth
    this.statusTarget.classList.add("is-visible")
    this.noticeTimer = window.setTimeout(() => {
      if (!this.hasStatusTarget) return
      this.statusTarget.classList.remove("is-visible")
      this.statusTarget.hidden = true
    }, NOTICE_MS)
  }
}

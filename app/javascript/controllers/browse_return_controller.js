import { Controller } from "@hotwired/stimulus"

const STORAGE_KEY = "registry-browse-return"

export default class extends Controller {
  connect() {
    this.beforeVisit = this.beforeVisit.bind(this)
    document.addEventListener("turbo:before-visit", this.beforeVisit)
    this.storeCurrentLocation()
  }

  disconnect() {
    document.removeEventListener("turbo:before-visit", this.beforeVisit)
  }

  beforeVisit() {
    this.storeCurrentLocation()
  }

  storeCurrentLocation() {
    try {
      const url = new URL(window.location.href)
      url.hash = "browse"
      window.sessionStorage.setItem(STORAGE_KEY, url.href)
    } catch {
      // Browsing still works when session storage is unavailable.
    }
  }
}

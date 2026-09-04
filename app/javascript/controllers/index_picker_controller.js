import { Controller } from "@hotwired/stimulus"
import { copyText } from "lib/clipboard"
import { beginClipboardOperation, clipboardOperationIsCurrent } from "lib/clipboard_feedback"

const WINDOW_SIZE = 9
const COMPACT_WINDOW_SIZE = 6
const GRID_COLUMNS = 3
const MAX_JSON_BYTES = 512 * 1024
const MAX_DESCRIPTION_LENGTH = 512
const SORTS = new Set(["downloads", "trending", "rating", "updated", "newest", "name"])
const SUGGESTION_TYPES = new Set(["plugin", "kind", "author", "tag", "category"])
const MATCH_TYPES = new Set(["sorted", "plugin", "kind", "author", "tag", "category", "text"])
const SEARCH_DELAY = 220
const WHEEL_STEP = 72
const RESPONSE_TIMEOUT_MS = 8000
const BROWSE_RELOAD_STORAGE_KEY = "registry:browse-reload-state"

export default class extends Controller {
  static values = {
    categories: Array, categoryLabels: Object, filterTags: Array, tags: Array
  }

  static targets = [
    "form", "input", "picker", "results", "row", "resultRange", "searchMatchCount", "live", "previous", "next",
    "fishPreview", "fishPrefix", "fishSuffix", "suggestions", "suggestion", "suggestionStatus",
    "visibleCategories", "breadcrumb", "pageStatus", "pageInput", "pageTotal",
    "sortLink", "clear", "filterToggle", "copyStatus"
  ]

  connect() {
    this.element.classList.add("is-enhanced")
    this.page = Number(this.pickerTarget.dataset.indexPickerPageValue || 1)
    const renderedPerPage = Number(this.pickerTarget.dataset.indexPickerPerPageValue || WINDOW_SIZE)
    this.compactPageMedia = window.matchMedia("(max-width: 620px)")
    this.perPage = renderedPerPage
    this.total = Number(this.pickerTarget.dataset.indexPickerTotalValue || 0)
    this.more = this.pickerTarget.dataset.indexPickerMoreValue === "true"
    this.endpoint = this.pickerTarget.dataset.indexPickerEndpointValue
    this.index = Number(this.pickerTarget.dataset.indexPickerSelectedIndex ?? -1)
    this.loadedQuery = this.canonicalQuery(this.inputTarget.value)
    this.suggestionQuery = this.loadedQuery
    this.suggestions = this.suggestionTargets.map((suggestion) => this.suggestionFromElement(suggestion))
    this.activeSuggestion = -1
    this.suppressedSuggestionQuery = null
    this.inputOwnsBrowseSelection = false
    this.inputTarget.value = this.loadedQuery
    this.syncInputWidth()
    this.canonicalizeHistoryQuery(this.loadedQuery)
    this.canonicalizeHistoryFilters()
    this.syncMobileSectionLinks()
    this.requestGeneration = 0
    this.responseTimeoutMs = RESPONSE_TIMEOUT_MS
    this.copyGeneration = 0
    this.wheelAccumulator = 0
    this.queuedNavigation = null
    this.pendingLoad = null
    this.plugins = this.rowTargets.map((row) => this.pluginFromRow(row))
    this.enhanceShareLinks()
    this.categoryCounts = this.filterCounts("category", this.categoriesValue)
    this.tagCounts = this.filterCounts("tag", this.filterTagsValue)
    this.filtersExpanded = this.hasActiveFilters()
    this.filterToggleTarget.hidden = false
    this.syncFilterDisclosure()
    this.recentBand = document.querySelector("[data-index-recent]")
    this.index = this.plugins.length ? Math.min(this.index, this.plugins.length - 1) : -1
    const storedBrowse = window.history.state?.registryBrowse || this.reloadedBrowseState()
    const storedPerPage = Number(storedBrowse?.perPage)
    const storedAnchor = Number(storedBrowse?.absoluteAnchor)
    const hasStoredWindow = [COMPACT_WINDOW_SIZE, WINDOW_SIZE].includes(storedPerPage) &&
      Number.isSafeInteger(storedAnchor) && storedAnchor >= 0
    const responsivePerPage = this.responsivePerPage()
    const responsivePage = hasStoredWindow ? Math.floor(storedAnchor / responsivePerPage) + 1 : this.page
    this.selectionCleared = hasStoredWindow && typeof storedBrowse.selectionCleared === "boolean" ?
      storedBrowse.selectionCleared : this.index < 0
    this.absoluteAnchor = hasStoredWindow ?
      storedAnchor : (this.page - 1) * this.perPage + Math.max(this.index, 0)
    const needsResponsiveLoad = renderedPerPage !== responsivePerPage || responsivePage !== this.page
    if (hasStoredWindow && !needsResponsiveLoad) {
      this.index = this.plugins.length && !this.selectionCleared ?
        Math.min(storedAnchor % responsivePerPage, this.plugins.length - 1) : -1
    }
    this.applySelection()
    if (!needsResponsiveLoad) this.replaceBrowseHistoryState()
    this.syncSortLinks()
    this.syncRecentVisibility()
    this.resizePageInput()

    this.handleDocumentKeydown = this.documentKeydown.bind(this)
    this.handleBeforeCache = this.beforeCache.bind(this)
    this.handlePopstate = this.popstate.bind(this)
    this.handleTurboLoad = this.turboLoad.bind(this)
    this.handleDocumentPointerdown = this.documentPointerdown.bind(this)
    this.handleSelectionChange = this.selectionChange.bind(this)
    this.handleCompactPageChange = this.syncResponsivePageSize.bind(this)
    this.handlePickerPointermove = () => this.pickerTarget.classList.add("is-pointer-mode")
    document.addEventListener("keydown", this.handleDocumentKeydown)
    document.addEventListener("pointerdown", this.handleDocumentPointerdown)
    document.addEventListener("selectionchange", this.handleSelectionChange)
    document.addEventListener("turbo:before-cache", this.handleBeforeCache)
    document.addEventListener("turbo:load", this.handleTurboLoad)
    this.pickerTarget.addEventListener("pointermove", this.handlePickerPointermove)
    this.compactPageMedia.addEventListener("change", this.handleCompactPageChange)
    window.addEventListener("popstate", this.handlePopstate, { capture: true })

    if (needsResponsiveLoad) {
      queueMicrotask(() => {
        if (!this.element.isConnected) return

        const perPage = this.responsivePerPage()
        const page = hasStoredWindow ? Math.floor(storedAnchor / perPage) + 1 : this.page
        const selectIndex = hasStoredWindow && !this.selectionCleared ? storedAnchor % perPage : this.index
        const absoluteAnchor = hasStoredWindow ? storedAnchor : null
        this.loadPage(page, { selectIndex, absoluteAnchor, perPage, history: "replace" })
      })
    }
  }

  disconnect() {
    this.element.classList.remove("is-enhanced")
    document.removeEventListener("keydown", this.handleDocumentKeydown)
    document.removeEventListener("pointerdown", this.handleDocumentPointerdown)
    document.removeEventListener("selectionchange", this.handleSelectionChange)
    document.removeEventListener("turbo:before-cache", this.handleBeforeCache)
    document.removeEventListener("turbo:load", this.handleTurboLoad)
    this.pickerTarget.removeEventListener("pointermove", this.handlePickerPointermove)
    this.compactPageMedia.removeEventListener("change", this.handleCompactPageChange)
    window.removeEventListener("popstate", this.handlePopstate, { capture: true })
    this.hideCopyStatus()
    window.clearTimeout(this.suggestionCloseTimer)
    window.clearTimeout(this.sortDisclosureTimer)
    cancelAnimationFrame(this.sortDisclosureFrame)
    this.cancelPendingRequest()
  }

  beforeCache() {
    this.element.classList.remove("is-enhanced")
    this.hideCopyStatus()
    this.cancelPendingRequest()
    window.clearTimeout(this.sortDisclosureTimer)
    cancelAnimationFrame(this.sortDisclosureFrame)
    this.closeSuggestions()
    const url = new URL(window.location.href)
    this.canonicalizeHistoryFilters(url)
    this.syncFilterInputs({
      sort: url.searchParams.get("sort") || "downloads",
      category: url.searchParams.get("category"),
      tag: url.searchParams.get("tag")
    })
    this.inputTarget.value = this.loadedQuery
    this.syncInputWidth()
    this.syncPickerState()
    this.updateVisibleCategories()
    this.updateDepth(this.loadedQuery)
    this.filterToggleTarget.hidden = true
    this.filterToggleTarget.setAttribute("aria-expanded", "false")
    this.element.classList.remove("is-filter-open")
    this.pickerTarget.classList.remove("is-pointer-mode")
    const sortDisclosure = this.element.querySelector("details.index-browse__sort")
    if (sortDisclosure) {
      sortDisclosure.open = false
      sortDisclosure.classList.remove("is-open", "is-closing")
    }
    this.syncSortLinks()
    this.syncRecentVisibility()
  }

  responsivePerPage() {
    return this.compactPageMedia.matches ? COMPACT_WINDOW_SIZE : WINDOW_SIZE
  }

  syncResponsivePageSize() {
    const perPage = this.responsivePerPage()
    const source = this.pendingLoad || {
      page: this.page,
      perPage: this.perPage,
      selectIndex: this.index
    }
    if (perPage === source.perPage || this.searchTimer) return

    const sourceIndex = source.selectIndex < 0 ? source.perPage - 1 : source.selectIndex
    const fallbackAnchor = (source.page - 1) * source.perPage + Math.max(sourceIndex, 0)
    const absoluteAnchor = Number.isSafeInteger(source.absoluteAnchor) ? source.absoluteAnchor :
      (Number.isSafeInteger(this.absoluteAnchor) ? this.absoluteAnchor : fallbackAnchor)
    const page = Math.floor(absoluteAnchor / perPage) + 1
    const selectIndex = this.selectionCleared ? 0 : absoluteAnchor % perPage
    const history = this.pendingLoad?.history ?? "replace"
    const focus = this.pendingLoad?.focus ?? false
    const reveal = this.pendingLoad?.reveal ?? false
    this.loadPage(page, {
      selectIndex, focus, reveal, absoluteAnchor, perPage, history, preserveQueuedNavigation: true
    })
  }

  turboLoad() {
    const stored = window.history.state?.registryBrowse
    const storedPerPage = Number(stored?.perPage)
    const storedAnchor = Number(stored?.absoluteAnchor)
    if (![COMPACT_WINDOW_SIZE, WINDOW_SIZE].includes(storedPerPage) ||
        !Number.isSafeInteger(storedAnchor) || storedAnchor < 0) return

    const perPage = this.responsivePerPage()
    const page = Math.floor(storedAnchor / perPage) + 1
    const selectionCleared = typeof stored.selectionCleared === "boolean" ? stored.selectionCleared : true
    const pendingMatches = this.pendingLoad?.page === page && this.pendingLoad?.perPage === perPage &&
      this.pendingLoad?.absoluteAnchor === storedAnchor
    const currentMatches = this.page === page && this.perPage === perPage &&
      this.absoluteAnchor === storedAnchor && this.selectionCleared === selectionCleared
    if (!pendingMatches && !currentMatches) this.popstate({ state: window.history.state })
  }

  popstate(event) {
    const stored = event.state?.registryBrowse
    if (!stored) return
    this.suppressedSuggestionQuery = null
    this.inputOwnsBrowseSelection = false
    const url = new URL(window.location.href)
    this.syncMobileSectionLinks(url)
    this.syncFormFromUrl(url)
    const urlPage = Number(url.searchParams.get("page") || 1)
    const page = Number.isSafeInteger(urlPage) && urlPage > 0 ? urlPage : 1
    this.selectionCleared = typeof stored.selectionCleared === "boolean" ? stored.selectionCleared : true
    const urlPerPage = Number(url.searchParams.get("per_page"))
    const sourcePerPage = [COMPACT_WINDOW_SIZE, WINDOW_SIZE].includes(stored?.perPage) ? stored.perPage :
      ([COMPACT_WINDOW_SIZE, WINDOW_SIZE].includes(urlPerPage) ? urlPerPage : WINDOW_SIZE)
    const storedAnchor = Number(stored?.absoluteAnchor)
    const absoluteAnchor = Number.isSafeInteger(storedAnchor) && storedAnchor >= 0 ?
      storedAnchor : (page - 1) * sourcePerPage
    const perPage = this.responsivePerPage()
    const responsivePage = Math.floor(absoluteAnchor / perPage) + 1
    const selectIndex = this.selectionCleared ? 0 : absoluteAnchor % perPage
    this.loadPage(responsivePage, { selectIndex, absoluteAnchor, perPage, history: "replace" })
  }

  search() {
    const query = this.canonicalQuery(this.inputTarget.value)
    this.inputOwnsBrowseSelection = false
    if (query !== this.suppressedSuggestionQuery) this.suppressedSuggestionQuery = null
    this.cancelPendingRequest()
    this.closeSuggestions()
    this.syncInputWidth()
    this.updateDepth(query, { pending: true })
    this.syncSortLinks()
    this.syncFilterLinks()
    this.syncRecentVisibility(1)
    this.searchTimer = window.setTimeout(() => {
      this.searchTimer = null
      this.loadPage(1, { history: "push" })
    }, SEARCH_DELAY)
  }

  clearSearch() {
    if (!this.canonicalQuery(this.inputTarget.value) && !this.loadedQuery) return
    this.suppressedSuggestionQuery = null
    this.inputOwnsBrowseSelection = false
    this.closeSuggestions()
    this.inputTarget.value = ""
    this.syncInputWidth()
    this.inputTarget.focus()
    this.loadPage(1, { history: "push" })
  }

  inputKeydown(event) {
    if (event.isComposing) return

    const unmodified = !event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey
    if (unmodified && event.key === "Escape" && this.filtersExpanded) {
      this.escapeFilters(event)
      return
    }
    if (unmodified && event.key === "Escape" && !this.suggestionsTarget.hidden) {
      event.preventDefault()
      this.closeSuggestions()
      return
    }
    if ((unmodified || (event.altKey && !event.ctrlKey && !event.metaKey && !event.shiftKey)) &&
        (event.key === "ArrowDown" || event.key === "ArrowUp") && !this.suggestionsTarget.hidden) {
      event.preventDefault()
      this.moveSuggestion(event.key === "ArrowDown" ? 1 : -1)
      return
    }
    if (unmodified && event.key === "ArrowRight" && !this.inputOwnsBrowseSelection && this.searchCaretAtEnd()) {
      const suggestion = this.inlineSuggestion()
      if (suggestion) {
        event.preventDefault()
        this.commitSuggestion(suggestion)
        return
      }
    }
    if (unmodified && event.key === "Enter" && !this.suggestionsTarget.hidden) {
      const suggestion = this.activeSuggestion >= 0 ?
        this.suggestions[this.activeSuggestion] : this.inlineSuggestion()
      if (suggestion) {
        event.preventDefault()
        this.commitSuggestion(suggestion)
        return
      }
    }

    if (event.key === "Escape") {
      event.preventDefault()
      this.clearSelection()
      if (this.inputTarget.value) {
        this.inputTarget.value = ""
        this.loadPage(1)
      } else {
        this.inputTarget.blur()
      }
    } else if (unmodified && (event.key === "ArrowRight" || event.key === "ArrowLeft") && this.inputOwnsBrowseSelection) {
      event.preventDefault()
      this.move(event.key === "ArrowRight" ? 1 : -1, { focus: false, reveal: true })
    } else if (unmodified && (event.key === "ArrowDown" || event.key === "ArrowUp")) {
      event.preventDefault()
      this.move(event.key === "ArrowDown" ? this.gridColumns() : -this.gridColumns(), { focus: false, reveal: true })
      this.inputOwnsBrowseSelection = this.index >= 0
    } else if (event.ctrlKey && !event.altKey && !event.metaKey && !event.shiftKey &&
               (event.key.toLowerCase() === "n" || event.key.toLowerCase() === "p")) {
      event.preventDefault()
      this.move(event.key.toLowerCase() === "n" ? 1 : -1, { focus: false, reveal: true })
      this.inputOwnsBrowseSelection = this.index >= 0
    } else if (unmodified && event.key === "Enter") {
      event.preventDefault()
      this.inputOwnsBrowseSelection = false
      if (this.pickerTarget.dataset.searchStale === "true") {
        window.location.assign(this.webUrl(1, this.canonicalQuery(this.inputTarget.value)).href)
      } else {
        this.submitSearch()
      }
    }
  }

  async submitSearch() {
    const query = this.canonicalQuery(this.inputTarget.value)
    const alreadyApplied = query === this.loadedQuery && !this.request && !this.searchTimer
    this.closeSuggestions()
    const applied = alreadyApplied || await this.loadPage(1, { history: "push" })
    if (!applied || !this.element.isConnected) return

    if (window.matchMedia("(pointer: coarse)").matches) this.inputTarget.blur()
    this.element.scrollIntoView({ block: "start", behavior: "auto" })
    const noun = this.total === 1 ? "plugin" : "plugins"
    const context = query ? ` for “${query}”` : ""
    this.liveTarget.textContent = `Showing ${this.total} ${noun}${context}.`
  }

  documentKeydown(event) {
    this.pickerTarget.classList.remove("is-pointer-mode")
    if (event.defaultPrevented || event.metaKey || event.ctrlKey || event.altKey || event.shiftKey) return
    if (event.target.closest("dialog[open], .theme-picker:not([hidden])")) return
    if (event.key === "Escape") {
      if (this.filtersExpanded) this.escapeFilters(event)
      else {
        event.preventDefault()
        this.clearSelection()
      }
      return
    }
    if (event.target.closest("input, textarea, select, [contenteditable]")) return

    const key = event.key.toLowerCase()
    const focusedRow = event.target.closest(".index-picker__row")
    const ordinaryControl = !focusedRow && event.target.closest("a, button, summary")
    if (ordinaryControl && (event.key === "Enter" || event.key === " " || event.code === "Space")) return

    const focusedIndex = focusedRow ? this.rowTargets.indexOf(focusedRow) : -1
    if (focusedIndex >= 0 && focusedIndex !== this.index) {
      this.hideCopyStatus()
      this.selectionCleared = false
      this.index = focusedIndex
      this.absoluteAnchor = (this.page - 1) * this.perPage + this.index
      this.applySelection()
      this.replaceBrowseHistoryState()
    }
    const columns = this.gridColumns()
    if (columns > 1 && event.key === "ArrowRight") {
      event.preventDefault()
      this.move(1, { reveal: true })
    } else if (columns > 1 && event.key === "ArrowLeft") {
      event.preventDefault()
      this.move(-1, { reveal: true })
    } else if (event.key === "ArrowDown") {
      event.preventDefault()
      this.move(columns, { reveal: true })
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.move(-columns, { reveal: true })
    } else if (event.key === "PageDown") {
      event.preventDefault()
      this.pageBy(1, { focus: true, reveal: true })
    } else if (event.key === "PageUp") {
      event.preventDefault()
      this.pageBy(-1, { focus: true, reveal: true })
    } else if (key === "j") {
      event.preventDefault()
      this.move(1, { reveal: true })
    } else if (key === "k") {
      event.preventDefault()
      this.move(-1, { reveal: true })
    } else if (key === "h") {
      event.preventDefault()
      this.move(-1, { reveal: true })
    } else if (key === "l") {
      event.preventDefault()
      this.move(1, { reveal: true })
    } else if (!focusedRow && event.key === "Enter" && this.index >= 0) {
      event.preventDefault()
      this.visitSelected()
    } else if ((event.key === " " || event.code === "Space") && this.index >= 0) {
      event.preventDefault()
      this.copySelected()
    } else if (event.key === "Backspace" && (this.hasContext() || this.page > 1)) {
      event.preventDefault()
      if (this.hasContext()) this.upLevel()
      else this.pageBy(-1, { focus: true, reveal: true })
    }
  }

  documentPointerdown(event) {
    if (!event.target.closest(".index-search")) this.closeSuggestions()
    if (!event.target.closest("details.index-browse__sort")) {
      this.closeSortDisclosure(this.element.querySelector("details.index-browse__sort"))
    }
    if (!this.pickerTarget.contains(event.target)) this.clearSelection({ announce: false })
  }

  resizePageInput() {
    const valueDigits = Math.max(1, this.pageInputTarget.value.replace(/\D/g, "").length)
    const maximumDigits = Math.max(1, this.pageInputTarget.max.replace(/\D/g, "").length)
    this.pageInputTarget.style.setProperty("--page-digits", Math.min(valueDigits, maximumDigits, 6))
  }

  dismissKeyHint(event) {
    if (event.key !== "Escape") return
    if (this.filtersExpanded) {
      this.escapeFilters(event)
      return
    }
    event.stopPropagation()
    event.preventDefault()
    event.currentTarget.classList.add("is-tooltip-dismissed")
  }

  resetKeyHint(event) {
    event.currentTarget.classList.remove("is-tooltip-dismissed")
  }

  toggleSortDisclosure(event) {
    event.preventDefault()
    const disclosure = event.currentTarget.closest("details")
    if (!disclosure) return

    window.clearTimeout(this.sortDisclosureTimer)
    cancelAnimationFrame(this.sortDisclosureFrame)
    if (disclosure.open) {
      this.closeSortDisclosure(disclosure)
    } else {
      disclosure.open = true
      disclosure.classList.remove("is-closing")
      this.sortDisclosureFrame = requestAnimationFrame(() => disclosure.classList.add("is-open"))
    }
  }

  closeSortDisclosure(disclosure, { focus = false } = {}) {
    if (!disclosure?.open) return
    window.clearTimeout(this.sortDisclosureTimer)
    cancelAnimationFrame(this.sortDisclosureFrame)
    disclosure.classList.remove("is-open")
    disclosure.classList.add("is-closing")
    const finish = () => {
      disclosure.open = false
      disclosure.classList.remove("is-closing")
      if (focus) disclosure.querySelector("summary")?.focus({ preventScroll: true })
    }
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) finish()
    else this.sortDisclosureTimer = window.setTimeout(finish, 180)
  }

  async sort(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const sort = event.currentTarget.dataset.sort
    if (!SORTS.has(sort)) return
    event.preventDefault()
    this.closeSuggestions()
    const disclosure = event.currentTarget.closest("details")
    const current = this.formSort()
    if (sort === current) {
      this.closeSortDisclosure(disclosure, { focus: true })
      return
    }
    const url = new URL(window.location.href)
    const urlSort = url.searchParams.get("sort") || "downloads"
    const fallback = SORTS.has(urlSort) ? urlSort : "downloads"

    this.replaceHiddenInput("sort", sort === "downloads" ? "" : sort)
    this.syncSortLinks()
    const loading = this.loadPage(1, { selectIndex: 0, history: "push" })
    const generation = this.requestGeneration
    const applied = await loading
    if (!this.element.isConnected || generation !== this.requestGeneration) {
      this.closeSortDisclosure(disclosure)
      return
    }

    if (!applied && !this.request && this.formSort() === sort) {
      this.replaceHiddenInput("sort", fallback === "downloads" ? "" : fallback)
      this.syncSortLinks()
      this.syncFilterLinks()
    }
    this.closeSortDisclosure(disclosure, { focus: true })
  }

  escapeFilters(event) {
    event.preventDefault()
    this.closeSuggestions()
    this.toggleFilters(event)
    this.filterToggleTarget.focus({ preventScroll: true })
  }

  async toggleFilters(event) {
    event.preventDefault()
    if (!this.filtersExpanded) {
      this.filtersExpanded = true
      this.syncFilterDisclosure()
      return
    }

    const form = new FormData(this.formTarget)
    const previous = { category: form.get("category") || "", tag: form.get("tag") || "" }
    this.filtersExpanded = false
    this.syncFilterDisclosure()
    if (!previous.category && !previous.tag) return

    this.replaceHiddenInput("category", "")
    this.replaceHiddenInput("tag", "")
    const loading = this.loadPage(1, { selectIndex: 0, history: "push" })
    const generation = this.requestGeneration
    const applied = await loading
    if (!this.element.isConnected || generation !== this.requestGeneration || applied) return

    if (!this.request && !this.hasActiveFilters()) {
      this.replaceHiddenInput("category", previous.category)
      this.replaceHiddenInput("tag", previous.tag)
      this.filtersExpanded = true
      this.syncFilterDisclosure()
      this.syncSortLinks()
      this.updateVisibleCategories()
      this.updateDepth(this.loadedQuery)
    }
  }

  hasActiveFilters() {
    const form = new FormData(this.formTarget)
    return Boolean(form.get("category") || form.get("tag"))
  }

  syncFilterDisclosure() {
    this.element.classList.toggle("is-filter-open", this.filtersExpanded)
    this.filterToggleTarget.classList.toggle("is-active", this.filtersExpanded)
    this.filterToggleTarget.setAttribute("aria-expanded", String(this.filtersExpanded))
    this.filterToggleTarget.setAttribute("aria-label", this.filtersExpanded ?
      (this.hasActiveFilters() ? "Clear plugin filters and hide" : "Hide plugin filters") :
      "Show plugin filters")
  }

  toggleCategory(event) {
    return this.toggleFilter(event, "category", this.categoriesValue)
  }

  toggleTag(event) {
    return this.toggleFilter(event, "tag", this.filterTagsValue)
  }

  async toggleFilter(event, name, allowedValues) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    const value = event.currentTarget.dataset[name]
    if (!allowedValues.includes(value)) return
    event.preventDefault()
    const previous = new FormData(this.formTarget).get(name) || ""
    const next = previous === value ? "" : value
    this.replaceHiddenInput(name, next)
    this.syncFilterDisclosure()
    const loading = this.loadPage(1, { selectIndex: 0, history: "push" })
    const generation = this.requestGeneration
    const applied = await loading
    if (!this.element.isConnected || generation !== this.requestGeneration) return

    if (!applied && !this.request && (new FormData(this.formTarget).get(name) || "") === next) {
      this.replaceHiddenInput(name, previous)
      this.syncFilterDisclosure()
      this.syncSortLinks()
      this.updateVisibleCategories()
      this.updateDepth(this.loadedQuery)
    }
    this.focusFilter(name, value)
  }

  focusFilter(name, value) {
    const replacement = [...this.visibleCategoriesTarget.querySelectorAll(`a[data-${name}]`)]
      .find((link) => link.dataset[name] === value)
    const focusTarget = replacement || this.visibleCategoriesTarget
    focusTarget.focus({ preventScroll: true })
  }

  async firstPage(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    this.closeSuggestions()

    const link = event.currentTarget
    const scrollPosition = { left: window.scrollX, top: window.scrollY }
    this.selectionCleared = false

    if (this.page === 1) {
      this.index = this.plugins.length ? 0 : -1
      this.absoluteAnchor = 0
      this.applySelection()
      this.syncPickerState()
      this.replaceBrowseHistoryState()
      link.focus({ preventScroll: true })
      this.liveTarget.textContent = "Browse is already on the first page."
      return
    }

    const applied = await this.loadPage(1, { selectIndex: 0, history: "push" })
    if (!applied || !this.element.isConnected) return

    window.scrollTo({ ...scrollPosition, behavior: "auto" })
    link.focus({ preventScroll: true })
    this.liveTarget.textContent = "Showing the first Browse page."
  }

  jumpPage(event) {
    event.preventDefault()
    const totalPages = Math.max(Math.ceil(this.total / this.perPage), 1)
    const requested = Number(this.pageInputTarget.value)
    if (!Number.isSafeInteger(requested)) {
      this.pageInputTarget.value = this.page
      return
    }
    const page = Math.min(Math.max(requested, 1), totalPages)
    this.pageInputTarget.value = page
    if (page === this.page) return
    this.loadPage(page, { selectIndex: 0, focus: true, history: "push" })
  }

  nextPage(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (this.pageBy(1, { focus: true })) event.preventDefault()
  }

  previousPage(event) {
    if (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    if (this.pageBy(-1, { focus: true })) event.preventDefault()
  }

  wheel(event) {
    if (event.metaKey || event.ctrlKey || event.altKey || event.shiftKey || this.gridColumns() === 1) return
    const delta = Math.abs(event.deltaY) >= Math.abs(event.deltaX) ? event.deltaY : event.deltaX
    if (!delta) return

    event.preventDefault()
    const step = delta > 0 ? this.gridColumns() : -this.gridColumns()
    const next = this.index + step
    const canMove = this.index < 0 || (next >= 0 && next < this.plugins.length) ||
      (next >= this.plugins.length && this.more) || (next < 0 && this.page > 1)
    if (!canMove) {
      this.wheelAccumulator = 0
      return
    }

    const unit = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : 1
    this.wheelAccumulator += delta * unit
    if (Math.abs(this.wheelAccumulator) < WHEEL_STEP) return
    const direction = this.wheelAccumulator > 0 ? 1 : -1
    this.wheelAccumulator = 0
    this.move(direction * this.gridColumns())
  }

  pageBy(direction, { focus = true, selectIndex = direction > 0 ? 0 : -1, reveal = false } = {}) {
    if (direction > 0 && !this.more) {
      if (reveal) this.revealBrowseSelection()
      return false
    }
    if (direction < 0 && this.page <= 1) {
      if (reveal) this.revealBrowseSelection()
      return false
    }
    if (focus) this.selectionCleared = false
    if (this.request) {
      this.queuedNavigation = { type: "page", direction, focus, selectIndex, reveal }
      return true
    }

    this.loadPage(this.page + direction, { selectIndex, focus, reveal, history: "push" })
    return true
  }

  move(step, { focus = true, reveal = false } = {}) {
    if (!this.plugins.length) return
    if (this.index < 0) {
      this.choose(step < 0 ? this.plugins.length - 1 : 0, { focus, reveal })
      return
    }
    if (this.request) {
      this.queuedNavigation = { type: "move", step, focus, reveal }
      return
    }
    const next = this.index + step

    if (next >= this.plugins.length && this.more) {
      this.pageBy(1, { focus, selectIndex: next - this.plugins.length, reveal })
    } else if (next < 0 && this.page > 1) {
      this.pageBy(-1, { focus, selectIndex: this.perPage + next, reveal })
    } else {
      this.choose(Math.min(Math.max(next, 0), this.plugins.length - 1), { focus, reveal })
    }
  }

  choose(index, { focus = false, reveal = false } = {}) {
    if (index < 0 || index >= this.plugins.length) return
    if (index !== this.index) this.hideCopyStatus()
    this.selectionCleared = false
    this.index = index
    this.absoluteAnchor = (this.page - 1) * this.perPage + this.index
    this.applySelection()
    this.replaceBrowseHistoryState()
    if (focus) this.rowTargets[index]?.querySelector(".index-picker__card-open")?.focus({ preventScroll: true })
    if (reveal) this.revealBrowseSelection()
  }

  revealBrowseSelection() {
    const row = this.rowTargets[this.index >= 0 ? this.index : 0]
    if (!row) return
    const rect = row.getBoundingClientRect()
    const margin = 12
    if (rect.top >= margin && rect.bottom <= window.innerHeight - margin) return
    const behavior = window.matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth"
    row.scrollIntoView({ block: "center", inline: "nearest", behavior })
  }

  applySelection() {
    this.rowTargets.forEach((row, index) => {
      row.classList.toggle("is-selected", index === this.index)
      row.removeAttribute("tabindex")
    })

    this.updateStatus()
  }

  clearSelection({ announce = true } = {}) {
    this.hideCopyStatus()
    this.selectionCleared = true
    this.inputOwnsBrowseSelection = false
    this.queuedNavigation = null
    if (this.index < 0) {
      this.replaceBrowseHistoryState()
      return
    }
    this.index = -1
    this.absoluteAnchor = (this.page - 1) * this.perPage
    if (document.activeElement?.closest?.(".index-picker__row")) document.activeElement.blur()
    this.applySelection()
    this.syncPickerState()
    this.replaceBrowseHistoryState()
    if (announce) this.liveTarget.textContent = "Plugin selection cleared."
  }

  updateStatus() {
    const hasResults = this.total > 0 && this.plugins.length > 0
    const start = hasResults ? (this.page - 1) * this.perPage + 1 : 0
    const end = hasResults ? Math.min(start + this.plugins.length - 1, this.total) : 0
    const selected = this.plugins.length && this.index >= 0 ? start + this.index : 0
    const range = document.createElement("strong")
    range.textContent = `${start}–${end}`
    const separator = document.createElement("span")
    separator.textContent = " / "
    separator.setAttribute("aria-hidden", "true")
    const total = document.createElement("b")
    total.textContent = new Intl.NumberFormat().format(this.total)
    this.resultRangeTarget.replaceChildren(range, separator, total)
    this.updateVisibleCategories()
    const totalPages = Math.max(Math.ceil(this.total / this.perPage), 1)
    this.pageInputTarget.value = this.page
    this.pageInputTarget.max = totalPages
    this.resizePageInput()
    this.pageTotalTarget.textContent = totalPages
    this.pageStatusTarget.setAttribute("aria-label", `Page ${this.page} of ${totalPages}`)
    const pageSizeLabel = this.perPage === WINDOW_SIZE ? "nine" :
      (this.perPage === COMPACT_WINDOW_SIZE ? "six" : String(this.perPage))
    this.previousTarget.setAttribute("aria-label", `Previous ${pageSizeLabel} plugin results`)
    this.nextTarget.setAttribute("aria-label", `Next ${pageSizeLabel} plugin results`)
    this.previousTarget.hidden = this.page <= 1
    this.nextTarget.hidden = !this.more
    this.previousTarget.href = this.webUrl(Math.max(this.page - 1, 1))
    this.nextTarget.href = this.webUrl(this.page + 1)
    this.updateDepth(this.loadedQuery)

    if (this.plugins.length && this.index >= 0) {
      this.liveTarget.textContent = `Selected ${this.plugins[this.index].name}, result ${selected} of ${this.total}`
    } else if (this.plugins.length) {
      this.liveTarget.textContent = ""
    } else if (this.total) {
      this.liveTarget.textContent = "No plugins on this page."
    } else {
      this.liveTarget.textContent = this.loadedQuery ? "No plugins match this search." : "No plugins published yet."
    }
  }

  async loadPage(page, {
    selectIndex = 0, focus = false, reveal = false, history = "replace", absoluteAnchor = null,
    perPage = this.responsivePerPage(), preserveQueuedNavigation = false
  } = {}) {
    window.clearTimeout(this.searchTimer)
    this.searchTimer = null
    if (!preserveQueuedNavigation) this.queuedNavigation = null
    this.request?.abort()
    const generation = ++this.requestGeneration
    const query = this.canonicalQuery(this.inputTarget.value)
    this.inputTarget.value = query
    this.syncInputWidth()
    this.syncFilterLinks()
    const request = new AbortController()
    const expected = this.expectedResponse(page, query, perPage)
    this.request = request
    const anchorOffset = this.selectionCleared ? 0 : (selectIndex < 0 ? perPage - 1 : selectIndex)
    const requestedAnchor = Number.isSafeInteger(absoluteAnchor) && absoluteAnchor >= 0 ?
      absoluteAnchor : (page - 1) * perPage + Math.max(anchorOffset, 0)
    this.pendingLoad = {
      page, perPage, selectIndex, focus, reveal, history, absoluteAnchor: requestedAnchor
    }
    this.pickerTarget.removeAttribute("data-search-stale")
    this.pickerTarget.setAttribute("aria-busy", "true")
    this.updateDepth(query, { pending: true })
    this.syncRecentVisibility(page)
    let applied = false

    try {
      const { data } = await this.requestJson(this.apiUrl(page, query, perPage), request)
      if (generation !== this.requestGeneration) return
      const next = this.normalizedResponse(data, expected)

      this.page = next.page
      this.perPage = next.perPage
      this.total = next.total
      this.more = next.more
      this.categoryCounts = next.categoryCounts
      this.tagCounts = next.tagCounts
      this.loadedQuery = next.query
      this.suggestionQuery = next.query
      this.suggestions = next.suggestions
      this.inputTarget.value = this.loadedQuery
      this.syncInputWidth()
      this.syncFilterInputs(next)
      this.syncSortLinks()
      this.syncRecentVisibility(this.page)
      this.renderSuggestions()
      this.plugins = next.plugins
      this.renderRows()
      this.index = this.plugins.length && !this.selectionCleared ?
        (selectIndex < 0 ? this.plugins.length - 1 : Math.min(selectIndex, this.plugins.length - 1)) : -1
      this.absoluteAnchor = requestedAnchor
      this.applySelection()
      this.syncPickerState()
      this.updateHistory(history)
      if (focus && this.plugins.length) {
        this.rowTargets[this.index]?.querySelector(".index-picker__card-open")?.focus({ preventScroll: true })
      }
      if (reveal) this.revealBrowseSelection()
      this.openSuggestions()
      applied = true
    } catch (error) {
      if (error.name !== "AbortError" && generation === this.requestGeneration) {
        this.pickerTarget.dataset.searchStale = "true"
        this.liveTarget.textContent = "Search could not be updated. Press Enter to run the server search."
        this.closeSuggestions()
        this.updateDepth(query, { unavailable: true })
        this.syncRecentVisibility(this.page)
      }
    } finally {
      if (generation === this.requestGeneration) {
        const queuedNavigation = applied ? this.queuedNavigation : null
        this.queuedNavigation = null
        this.pendingLoad = null
        this.request = null
        this.pickerTarget.removeAttribute("aria-busy")
        if (queuedNavigation?.type === "page") {
          this.pageBy(queuedNavigation.direction, {
            focus: queuedNavigation.focus,
            selectIndex: queuedNavigation.selectIndex,
            reveal: queuedNavigation.reveal
          })
        } else if (queuedNavigation?.type === "move") {
          this.move(queuedNavigation.step, { focus: queuedNavigation.focus, reveal: queuedNavigation.reveal })
        }
      }
    }
    return applied
  }

  renderRows({ fill = true } = {}) {
    this.hideCopyStatus()
    this.resultsTarget.replaceChildren()
    this.plugins.forEach((plugin) => this.resultsTarget.append(this.resultCard(plugin)))
    if (!fill) return

    const emptyText = this.page > 1 ? "No plugins on this page." :
      (this.canonicalQuery(this.inputTarget.value) || this.formContext() ? "No plugins match this search." : "No plugins published yet.")
    for (let index = this.plugins.length; index < this.perPage; index += 1) {
      this.resultsTarget.append(this.emptyCard(index === 0 ? emptyText : ""))
    }
  }

  resultCard(plugin) {
    const link = document.createElement("article")
    const absoluteIndex = this.absoluteIndex(this.resultsTarget.querySelectorAll(".index-picker__row").length)
    link.className = "index-picker__row index-picker__card"
    link.id = `plugin-option-${this.page}-${absoluteIndex}`
    link.dataset.url = plugin.url
    link.dataset.indexPickerTarget = "row"
    link.dataset.name = plugin.name
    link.dataset.publisher = plugin.publisher
    link.dataset.category = plugin.category || "other"
    link.dataset.kinds = JSON.stringify(plugin.kinds)
    link.dataset.tags = JSON.stringify(plugin.tags)
    link.dataset.summary = plugin.summary || ""
    link.dataset.previewUrl = plugin.preview?.url || ""
    link.dataset.previewWidth = plugin.preview?.width || ""
    link.dataset.previewHeight = plugin.preview?.height || ""
    link.dataset.installCommand = plugin.installCommand || ""
    link.dataset.matchType = plugin.match.type
    link.dataset.matchValue = plugin.match.value
    link.dataset.latestVersion = plugin.latestVersion || ""
    link.dataset.isNew = plugin.isNew
    link.dataset.upvotes = plugin.upvotes
    link.dataset.views = plugin.views
    link.dataset.downloads = plugin.downloads
    link.dataset.verified = plugin.verified
    link.dataset.sizeBytes = plugin.sizeBytes ?? ""

    const open = document.createElement("a")
    open.className = "index-picker__card-open"
    open.href = plugin.url
    open.setAttribute("aria-label", `Open ${plugin.publisher}/${plugin.name} plugin details`)

    const visual = document.createElement("span")
    visual.className = "index-picker__card-visual"
    if (plugin.preview?.url) {
      const image = document.createElement("img")
      image.src = plugin.preview.url
      image.alt = ""
      image.loading = "lazy"
      image.decoding = "async"
      if (plugin.preview.width) image.width = plugin.preview.width
      if (plugin.preview.height) image.height = plugin.preview.height
      visual.append(image)
    } else {
      const fallback = document.createElement("span")
      fallback.className = "index-picker__card-fallback"
      const label = document.createElement("b")
      label.textContent = "preview unavailable"
      const summary = document.createElement("span")
      summary.textContent = plugin.summary || "No preview artifact was published."
      fallback.append(label, summary)
      visual.append(fallback)
    }

    const footer = document.createElement("span")
    footer.className = "index-picker__card-foot"
    const primary = document.createElement("span")
    primary.className = "index-picker__card-primary"
    const title = document.createElement("span")
    title.className = "index-picker__card-title"
    const name = document.createElement("a")
    name.className = "index-picker__card-name"
    name.href = plugin.url
    name.textContent = plugin.name
    name.title = "Share plugin link"
    name.dataset.action = "click->index-picker#sharePlugin keydown.space->index-picker#sharePlugin"
    name.dataset.shareLabel = `Copy link to ${plugin.publisher}/${plugin.name}`
    name.setAttribute("aria-label", name.dataset.shareLabel)
    name.setAttribute("translate", "no")
    title.append(name)

    const signals = document.createElement("span")
    signals.className = "index-picker__card-signals"
    const signalDescription = document.createElement("span")
    signalDescription.className = "visually-hidden"
    signalDescription.textContent = `${plugin.isNew ? "New plugin, " : ""}${plugin.downloads} download${plugin.downloads === 1 ? "" : "s"}, ${plugin.upvotes} upvote${plugin.upvotes === 1 ? "" : "s"}, ${plugin.views} view${plugin.views === 1 ? "" : "s"}`
    signals.append(signalDescription)
    if (plugin.isNew) {
      const badge = document.createElement("mark")
      badge.textContent = "new"
      badge.setAttribute("aria-hidden", "true")
      signals.append(badge)
    }
    const downloads = document.createElement("span")
    downloads.textContent = `↓ ${this.compactNumber(plugin.downloads)}`
    downloads.setAttribute("aria-hidden", "true")
    const upvotes = document.createElement("span")
    upvotes.append(this.signalIcon("upvote"), document.createTextNode(` ${this.compactNumber(plugin.upvotes)}`))
    upvotes.setAttribute("aria-hidden", "true")
    const views = document.createElement("span")
    views.append(this.signalIcon("view"), document.createTextNode(` ${this.compactNumber(plugin.views)}`))
    views.setAttribute("aria-hidden", "true")
    signals.append(downloads, upvotes, views)
    primary.append(title, signals)

    const secondary = document.createElement("span")
    secondary.className = "index-picker__card-secondary"
    const publisher = document.createElement("span")
    publisher.className = "index-picker__card-publisher"
    publisher.textContent = plugin.publisher.toLowerCase()
    publisher.setAttribute("translate", "no")
    const artifact = document.createElement("b")
    artifact.className = "index-picker__card-artifact"
    artifact.setAttribute("translate", "no")
    const verification = document.createElement("span")
    verification.className = plugin.verified ? "is-verified" : "is-pending"
    verification.setAttribute("aria-label", plugin.verified ?
      "Verified artifact: passed registry review" : "Artifact verification pending")
    verification.textContent = plugin.verified ? "Verified" : "Pending"
    artifact.append(verification)
    if (plugin.sizeBytes !== null) {
      const size = document.createElement("span")
      size.textContent = this.formatBytes(plugin.sizeBytes)
      artifact.append(size)
    }
    const version = document.createElement("span")
    version.textContent = plugin.latestVersion ? `v${plugin.latestVersion}` : "version pending"
    artifact.append(version)
    secondary.append(publisher, artifact)
    footer.append(primary, secondary)

    link.append(open, visual, footer)
    return link
  }

  signalIcon(kind) {
    const namespace = "http://www.w3.org/2000/svg"
    const icon = document.createElementNS(namespace, "svg")
    icon.classList.add(`index-picker__${kind}-glyph`)
    icon.setAttribute("viewBox", "0 0 16 16")
    icon.setAttribute("aria-hidden", "true")
    icon.setAttribute("focusable", "false")

    const path = document.createElementNS(namespace, "path")
    path.setAttribute("d", kind === "upvote" ?
      "M5.5 7 8 2.5c.3-.6 1.2-.4 1.2.3V6h3.2c.8 0 1.4.7 1.2 1.5l-1 5c-.1.6-.6 1-1.2 1H5.5m0-6.5v6.5H2.5V7h3Z" :
      "M1.5 8s2.3-4 6.5-4 6.5 4 6.5 4-2.3 4-6.5 4S1.5 8 1.5 8Z")
    icon.append(path)
    if (kind === "view") {
      const pupil = document.createElementNS(namespace, "circle")
      pupil.setAttribute("cx", "8")
      pupil.setAttribute("cy", "8")
      pupil.setAttribute("r", "1.7")
      icon.append(pupil)
    }
    return icon
  }

  emptyCard(message) {
    const recoverable = Boolean(message && this.page > 1)
    const card = document.createElement(recoverable ? "a" : "span")
    card.className = "index-picker__card index-picker__card--empty"
    if (recoverable) {
      card.href = this.webUrl(1)
    } else {
      card.setAttribute("aria-hidden", "true")
    }
    if (message) {
      const label = document.createElement("b")
      label.textContent = recoverable ? `${message} Back to the first page →` : message
      card.append(label)
    } else {
      const marker = document.createElement("i")
      marker.textContent = "~"
      card.append(marker)
    }
    return card
  }

  filterCounts(name, values) {
    return Object.fromEntries(values.map((value) => {
      const link = [...this.visibleCategoriesTarget.querySelectorAll(`a[data-${name}]`)]
        .find((candidate) => candidate.dataset[name] === value)
      const count = Number(link?.querySelector("strong")?.textContent || 0)
      return [value, Number.isSafeInteger(count) && count >= 0 ? count : 0]
    }))
  }

  updateVisibleCategories() {
    const form = new FormData(this.formTarget)
    const categoryNodes = this.categoriesValue.filter((category) =>
      (this.categoryCounts[category] || 0) > 0 || form.get("category") === category || category === "kids"
    ).map((category) => this.filterOption(
      "category", category, this.categoryLabelsValue[category] || category,
      this.categoryCounts[category] || 0, form.get("category") === category
    ))
    const tagNodes = this.filterTagsValue.filter((tag) =>
      (this.tagCounts[tag] || 0) > 0 || form.get("tag") === tag
    ).map((tag) => this.filterOption(
      "tag", tag, tag, this.tagCounts[tag] || 0, form.get("tag") === tag
    ))
    const filters = [ ...categoryNodes, ...tagNodes ]

    if (filters.length) {
      this.visibleCategoriesTarget.replaceChildren(...filters)
    } else {
      const empty = document.createElement("i")
      empty.className = "index-picker__category"
      empty.dataset.category = "other"
      empty.textContent = "none"
      this.visibleCategoriesTarget.replaceChildren(empty)
    }
  }

  filterOption(name, value, label, count, active) {
    const link = document.createElement("a")
    link.className = `index-picker__filter-option index-picker__${name}${active ? " is-active" : ""}`
    link.href = this.filterUrl(name, value)
    link.dataset[name] = value
    link.dataset.action = `click->index-picker#toggle${name[0].toUpperCase()}${name.slice(1)}`
    link.setAttribute("aria-label", active ?
      `Clear ${label} ${name} filter, ${count} registry plugins` :
      `Filter by ${label} ${name}, ${count} registry plugins`)
    const text = document.createElement("span")
    text.append(document.createTextNode(`${label} `))
    const total = document.createElement("strong")
    total.textContent = count
    text.append(total)
    link.append(text)
    return link
  }

  suggestionFromElement(element) {
    return {
      type: element.dataset.suggestionType,
      label: element.dataset.suggestionLabel,
      completion: element.dataset.completion,
      detail: element.dataset.suggestionDetail || ""
    }
  }

  renderSuggestions() {
    const summary = document.createElement("div")
    summary.className = "index-search__suggestion-summary"
    summary.setAttribute("role", "presentation")
    summary.setAttribute("aria-hidden", "true")
    const label = document.createElement("span")
    label.textContent = `complete “${this.suggestionQuery}”`
    const instructions = document.createElement("small")
    instructions.textContent = "↓ choose · → / enter accept"
    summary.append(label, instructions)

    const options = this.suggestions.map((suggestion, index) => {
      const option = document.createElement("button")
      option.id = `search-suggestion-${index}`
      option.type = "button"
      option.tabIndex = -1
      option.setAttribute("role", "option")
      option.setAttribute("aria-selected", "false")
      option.dataset.indexPickerTarget = "suggestion"
      option.dataset.action = "pointerdown->index-picker#keepSuggestionFocus click->index-picker#acceptSuggestion"
      option.dataset.completion = suggestion.completion
      option.dataset.suggestionType = suggestion.type
      option.dataset.suggestionLabel = suggestion.label
      option.dataset.suggestionDetail = suggestion.detail
      const name = document.createElement("span")
      name.textContent = suggestion.label
      const detail = document.createElement("small")
      detail.textContent = `${suggestion.type}${suggestion.detail ? ` · ${suggestion.detail}` : ""}`
      option.append(name, detail)
      return option
    })
    this.suggestionsTarget.replaceChildren(summary, ...options)
  }

  openSuggestions() {
    window.clearTimeout(this.suggestionCloseTimer)
    const query = this.canonicalQuery(this.inputTarget.value)
    if (query && query === this.suppressedSuggestionQuery) {
      this.closeSuggestions()
      return
    }
    if (!query || query !== this.suggestionQuery || !this.suggestions.length || document.activeElement !== this.inputTarget) {
      this.closeSuggestions()
      return
    }
    this.suggestionsTarget.hidden = false
    this.inputTarget.setAttribute("aria-expanded", "true")
    this.suggestionStatusTarget.textContent = `${this.suggestions.length} search suggestions available. Press Down Arrow to choose a suggestion, or Enter or Right Arrow to accept the inline completion.`
    this.updateFishPreview()
  }

  scheduleCloseSuggestions() {
    window.clearTimeout(this.suggestionCloseTimer)
    this.suggestionCloseTimer = window.setTimeout(() => this.closeSuggestions(), 100)
  }

  closeSuggestions() {
    window.clearTimeout(this.suggestionCloseTimer)
    this.suggestionsTarget.hidden = true
    this.fishPreviewTarget.hidden = true
    this.activeSuggestion = -1
    this.suggestionTargets.forEach((option) => {
      option.setAttribute("aria-selected", "false")
      option.classList.remove("is-active")
    })
    this.inputTarget.setAttribute("aria-expanded", "false")
    this.inputTarget.removeAttribute("aria-activedescendant")
    this.suggestionStatusTarget.textContent = ""
  }

  moveSuggestion(offset) {
    if (!this.suggestions.length) return
    this.activeSuggestion = this.activeSuggestion < 0 ?
      (offset > 0 ? 0 : this.suggestions.length - 1) :
      (this.activeSuggestion + offset + this.suggestions.length) % this.suggestions.length
    this.suggestionTargets.forEach((option, index) => {
      const active = index === this.activeSuggestion
      option.setAttribute("aria-selected", String(active))
      option.classList.toggle("is-active", active)
    })
    const active = this.suggestionTargets[this.activeSuggestion]
    if (active) this.inputTarget.setAttribute("aria-activedescendant", active.id)
    this.suggestionStatusTarget.textContent = `${this.suggestions[this.activeSuggestion].label}, suggestion ${this.activeSuggestion + 1} of ${this.suggestions.length}. Press Enter to accept.`
    this.updateFishPreview()
  }

  keepSuggestionFocus(event) {
    event.preventDefault()
  }

  acceptSuggestion(event) {
    event.preventDefault()
    const index = this.suggestionTargets.indexOf(event.currentTarget)
    if (index >= 0) this.commitSuggestion(this.suggestions[index])
  }

  commitSuggestion(suggestion) {
    if (!suggestion) return
    this.inputTarget.value = this.canonicalQuery(suggestion.completion)
    this.inputTarget.setSelectionRange(this.inputTarget.value.length, this.inputTarget.value.length)
    this.suppressedSuggestionQuery = this.inputTarget.value
    this.closeSuggestions()
    this.search()
    this.inputTarget.focus()
    this.suggestionStatusTarget.textContent = `Completed search with ${suggestion.label}.`
  }

  inlineSuggestion() {
    const query = this.canonicalQuery(this.inputTarget.value)
    if (!query || query !== this.suggestionQuery || !this.searchCaretAtEnd()) return null
    const folded = query.toLocaleLowerCase()
    const candidates = this.activeSuggestion >= 0 ? [this.suggestions[this.activeSuggestion]] : this.suggestions
    return candidates.find((suggestion) => suggestion && suggestion.completion.length > query.length &&
      suggestion.completion.toLocaleLowerCase().startsWith(folded)) || null
  }

  updateFishPreview() {
    const suggestion = this.inlineSuggestion()
    if (!suggestion || document.activeElement !== this.inputTarget) {
      this.fishPreviewTarget.hidden = true
      return
    }
    const query = this.canonicalQuery(this.inputTarget.value)
    this.fishPrefixTarget.textContent = query
    this.fishSuffixTarget.textContent = suggestion.completion.slice(query.length)
    this.fishPreviewTarget.hidden = false
  }

  selectionChange() {
    if (document.activeElement === this.inputTarget) this.updateFishPreview()
  }

  searchCaretAtEnd() {
    return this.inputTarget.selectionStart === this.inputTarget.value.length &&
      this.inputTarget.selectionEnd === this.inputTarget.value.length
  }

  updateDepth(query, { pending = false, unavailable = false } = {}) {
    const cleanQuery = query.trim()
    const depthQuery = pending ? this.loadedQuery.trim() : cleanQuery
    const context = [ depthQuery ? `query / ${depthQuery}` : "", this.formContext() ]
      .filter(Boolean).join(" + ")
    const hasContext = Boolean(context)
    this.inputTarget.closest(".index-search")?.classList.toggle("is-active", Boolean(depthQuery))
    this.element.classList.toggle("index-console--has-context", hasContext)
    this.breadcrumbTarget.textContent = `all${hasContext ? ` › ${context.replaceAll(" / ", ":")}` : ""} › results`

    this.searchMatchCountTarget.hidden = !cleanQuery
    if (!cleanQuery) return
    this.searchMatchCountTarget.dataset.state = unavailable ? "stale" : (pending ? "loading" : "live")
    this.searchMatchCountTarget.textContent = pending ? "…" :
      (unavailable ? "—" : new Intl.NumberFormat().format(this.total))
    this.searchMatchCountTarget.setAttribute("aria-label", pending ? "Searching plugins" :
      (unavailable ? "Plugin search unavailable" : `${this.total} ${this.total === 1 ? "plugin" : "plugins"} found for ${cleanQuery}`))
  }

  syncInputWidth() {
    const length = Array.from(this.inputTarget.value).length
    this.inputTarget.style.width = `${length ? Math.min(Math.max(length + 1, 12), 48) : 48}ch`
    const active = Boolean(this.canonicalQuery(this.inputTarget.value))
    this.clearTarget.hidden = !active
  }

  asciiStrip(value) {
    return String(value).replace(/^[\u0000\u0009-\u000d\u0020]+|[\u0000\u0009-\u000d\u0020]+$/g, "")
  }

  canonicalQuery(value) {
    return Array.from(this.asciiStrip(String(value).normalize("NFC"))).slice(0, 160).join("")
  }

  canonicalizeHistoryQuery(query, url = new URL(window.location.href)) {
    const current = url.searchParams.get("q") || ""
    if (current === query) return
    if (query) url.searchParams.set("q", query)
    else url.searchParams.delete("q")
    window.history.replaceState(window.history.state, "", url)
  }

  canonicalizeHistoryFilters(url = new URL(window.location.href)) {
    const invalidSort = url.searchParams.has("sort") && !SORTS.has(url.searchParams.get("sort"))
    const invalidCategory = url.searchParams.has("category") && !this.categoriesValue.includes(url.searchParams.get("category"))
    const invalidTag = url.searchParams.has("tag") && !this.tagsValue.includes(url.searchParams.get("tag"))
    if (!invalidSort && !invalidCategory && !invalidTag) return
    if (invalidSort) url.searchParams.delete("sort")
    if (invalidCategory) url.searchParams.delete("category")
    if (invalidTag) url.searchParams.delete("tag")
    window.history.replaceState(window.history.state, "", url)
  }

  gridColumns() {
    return window.matchMedia("(max-width: 620px)").matches ? 1 : GRID_COLUMNS
  }

  syncFormFromUrl(url) {
    const query = this.canonicalQuery(url.searchParams.get("q") || "")
    this.inputTarget.value = query
    this.syncInputWidth()
    this.canonicalizeHistoryQuery(query, url)
    this.canonicalizeHistoryFilters(url)
    this.syncFilterInputs({
      sort: url.searchParams.get("sort") || "downloads",
      category: url.searchParams.get("category"),
      tag: url.searchParams.get("tag")
    })
    if (this.hasActiveFilters()) {
      this.filtersExpanded = true
      this.syncFilterDisclosure()
    }
    this.syncSortLinks()
    const page = Number(url.searchParams.get("page") || 1)
    this.syncRecentVisibility(Number.isSafeInteger(page) && page > 0 ? page : 1)
  }

  syncFilterInputs({ sort, category, tag }) {
    this.replaceHiddenInput("sort", sort && sort !== "downloads" ? sort : "")
    this.replaceHiddenInput("category", category || "")
    this.replaceHiddenInput("tag", tag || "")
  }

  replaceHiddenInput(name, value) {
    this.formTarget.querySelectorAll(`input[type="hidden"][name="${name}"]`).forEach((input) => input.remove())
    if (!value) return
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    this.formTarget.append(input)
  }

  syncSortLinks() {
    const activeSort = this.formSort()
    const baseParams = this.formParams()
    this.sortLinkTargets.forEach((link) => {
      const sort = link.dataset.sort
      const params = new URLSearchParams(baseParams)
      if (sort === "downloads") params.delete("sort")
      else params.set("sort", sort)
      const url = new URL(this.formTarget.action, window.location.origin)
      url.search = params.toString()
      link.href = url
      link.classList.toggle("is-active", sort === activeSort)
      if (sort === activeSort) link.setAttribute("aria-current", "page")
      else link.removeAttribute("aria-current")
    })
  }

  syncRecentVisibility() {
    if (this.recentBand) this.recentBand.hidden = false
  }

  formContext() {
    const data = new FormData(this.formTarget)
    return [
      data.get("category") ? `category / ${data.get("category")}` : "",
      data.get("tag") ? `tag / ${data.get("tag")}` : ""
    ].filter(Boolean).join(" + ")
  }

  hasContext() {
    return Boolean(this.canonicalQuery(this.inputTarget.value) || this.formContext())
  }

  upLevel() {
    if (this.canonicalQuery(this.inputTarget.value)) {
      this.inputTarget.value = ""
      this.loadPage(1, { history: "push", focus: true })
      return
    }

    const input = this.formTarget.querySelector("input[name='tag'], input[name='category']")
    if (!input) return
    input.remove()
    this.loadPage(1, { history: "push", focus: true })
  }

  async requestJson(url, request, maxBytes = MAX_JSON_BYTES, timeoutMs = this.responseTimeoutMs) {
    if (!Number.isFinite(timeoutMs) || timeoutMs <= 0) throw new DOMException("Search response timed out", "TimeoutError")
    const timeoutError = new DOMException("Search response timed out", "TimeoutError")
    let timedOut = false
    const timer = window.setTimeout(() => {
      timedOut = true
      request.abort(timeoutError)
    }, timeoutMs)

    try {
      const response = await fetch(url, {
        cache: "no-store",
        headers: { Accept: "application/json" },
        signal: request.signal
      })
      if (!response.ok) {
        await this.cancelResponse(response)
        throw new Error(`Search request failed with ${response.status}`)
      }
      const envelope = await this.boundedJson(response, maxBytes, request.signal)
      if (timedOut) throw timeoutError
      return envelope
    } catch (error) {
      if (timedOut) throw timeoutError
      throw error
    } finally {
      window.clearTimeout(timer)
    }
  }

  async cancelResponse(response) {
    try {
      await response.body?.cancel()
    } catch {
    }
  }

  async boundedJson(response, maxBytes = MAX_JSON_BYTES, signal = null) {
    const limit = Math.min(MAX_JSON_BYTES, maxBytes)
    if (!Number.isSafeInteger(limit) || limit < 1) {
      await this.cancelResponse(response)
      throw new TypeError("Invalid search response size")
    }
    const declared = response.headers.get("Content-Length")
    if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > limit)) {
      await this.cancelResponse(response)
      throw new TypeError("Invalid search response size")
    }

    if (!response.body?.getReader) {
      await this.cancelResponse(response)
      throw new TypeError("Bounded response streaming is unavailable")
    }

    const reader = response.body.getReader()
    const cancelReader = () => { reader.cancel(signal?.reason).catch(() => {}) }
    if (signal?.aborted) cancelReader()
    else signal?.addEventListener("abort", cancelReader, { once: true })
    const chunks = []
    let size = 0
    try {
      while (true) {
        const { done, value } = await reader.read()
        if (done) break
        size += value.byteLength
        if (size > limit) {
          await reader.cancel()
          throw new TypeError("Invalid search response size")
        }
        chunks.push(value)
      }
    } finally {
      signal?.removeEventListener("abort", cancelReader)
      reader.releaseLock()
    }

    const bytes = new Uint8Array(size)
    let offset = 0
    chunks.forEach((chunk) => {
      bytes.set(chunk, offset)
      offset += chunk.byteLength
    })
    return {
      data: JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes)),
      byteLength: size
    }
  }

  normalizedResponse(data, expected = {}) {
    if (!data || typeof data !== "object" || Array.isArray(data) || data.schema_version !== 1 ||
        typeof data.catalog_revision !== "string" || !/^[a-f0-9]{64}$/.test(data.catalog_revision)) {
      throw new TypeError("Invalid search response")
    }
    const page = data.page
    const query = data.query
    if (!page || typeof page !== "object" || !query || typeof query !== "object") throw new TypeError("Invalid search metadata")
    if (!Number.isSafeInteger(page.number) || page.number < 1 || page.number !== expected.page ||
        page.per_page !== expected.perPage || !Number.isSafeInteger(page.total) || page.total < 0 ||
        typeof page.more !== "boolean" || page.more !== (page.total > page.number * page.per_page)) {
      throw new TypeError("Invalid search page")
    }
    if (typeof query.q !== "string" || this.canonicalQuery(query.q) !== query.q ||
        query.q !== expected.query || !SORTS.has(query.sort) || query.sort !== expected.sort ||
        (query.category !== null && (typeof query.category !== "string" || query.category.length > 64)) ||
        (query.tag !== null && (typeof query.tag !== "string" || query.tag.length > 64)) ||
        query.category !== expected.category || query.tag !== expected.tag) {
      throw new TypeError("Invalid search query")
    }
    const plan = data.plan
    if (!plan || typeof plan !== "object" || Array.isArray(plan) ||
        ![plan.parse, plan.scope, plan.match].every((value) => typeof value === "string" && value.length <= 512)) {
      throw new TypeError("Invalid search plan")
    }
    if (!Array.isArray(data.suggestions) || data.suggestions.length > 6) {
      throw new TypeError("Invalid search suggestions")
    }
    const suggestions = data.suggestions.map((suggestion) => {
      if (!suggestion || typeof suggestion !== "object" || !SUGGESTION_TYPES.has(suggestion.type) ||
          typeof suggestion.label !== "string" || !suggestion.label || suggestion.label.length > 160 ||
          typeof suggestion.completion !== "string" || !suggestion.completion ||
          this.canonicalQuery(suggestion.completion) !== suggestion.completion ||
          typeof suggestion.detail !== "string" || suggestion.detail.length > 160 ||
          [suggestion.label, suggestion.completion, suggestion.detail].some((value) => /[\u0000-\u001f\u007f-\u009f]/.test(value))) {
        throw new TypeError("Invalid search suggestion")
      }
      return suggestion
    })

    const categories = data.taxonomy?.categories
    if (!Array.isArray(categories) || categories.length !== this.categoriesValue.length) {
      throw new TypeError("Invalid search taxonomy")
    }
    const categoryCounts = Object.fromEntries(categories.map((category, index) => {
      const expectedSlug = this.categoriesValue[index]
      if (!category || typeof category !== "object" || category.slug !== expectedSlug ||
          typeof category.label !== "string" || !category.label || category.label.length > 160 ||
          !Number.isSafeInteger(category.count) || category.count < 0 ||
          !Number.isSafeInteger(category.match_count) || category.match_count < 0 ||
          category.match_count > category.count) {
        throw new TypeError("Invalid search category")
      }
      return [category.slug, category.count]
    }))

    const tagCountsPayload = data.taxonomy?.tag_counts
    if (!tagCountsPayload || typeof tagCountsPayload !== "object" || Array.isArray(tagCountsPayload) ||
        Object.keys(tagCountsPayload).length !== this.filterTagsValue.length) {
      throw new TypeError("Invalid search tag counts")
    }
    const tagCounts = Object.fromEntries(this.filterTagsValue.map((tag) => {
      const count = tagCountsPayload[tag]
      if (!Object.hasOwn(tagCountsPayload, tag) || !Number.isSafeInteger(count) || count < 0) {
        throw new TypeError("Invalid search tag count")
      }
      return [tag, count]
    }))

    const remaining = Math.max(page.total - (page.number - 1) * page.per_page, 0)
    if (!Array.isArray(data.plugins) || data.plugins.length !== Math.min(page.per_page, remaining)) {
      throw new TypeError("Invalid search plugins")
    }

    const plugins = data.plugins.map((plugin) => {
      const validArray = (values) => Array.isArray(values) && values.length <= 64 &&
        values.every((value) => typeof value === "string" && value.length <= 160)
      if (!plugin || typeof plugin !== "object" || typeof plugin.id !== "string" || !plugin.id || plugin.id.length > 321 ||
          typeof plugin.name !== "string" || !plugin.name || plugin.name.length > 160 ||
          typeof plugin.publisher !== "string" || !plugin.publisher || plugin.publisher.length > 160 ||
          typeof plugin.url !== "string" || !plugin.url || plugin.url.length > 2048 ||
          !validArray(plugin.kinds) || !validArray(plugin.tags) ||
          (plugin.category !== null && (typeof plugin.category !== "string" || plugin.category.length > 64)) ||
          (plugin.summary !== null && (typeof plugin.summary !== "string" ||
            Array.from(plugin.summary).length > MAX_DESCRIPTION_LENGTH)) ||
          (plugin.latest_version !== null && (typeof plugin.latest_version !== "string" || plugin.latest_version.length > 160 ||
            /[\u0000-\u001f\u007f-\u009f]/.test(plugin.latest_version))) ||
          !Number.isSafeInteger(plugin.downloads) || plugin.downloads < 0 ||
          !plugin.match || typeof plugin.match !== "object" || !MATCH_TYPES.has(plugin.match.type) ||
          typeof plugin.match.value !== "string" || !plugin.match.value || plugin.match.value.length > 160 ||
          !plugin.card || typeof plugin.card !== "object" || Array.isArray(plugin.card) ||
          typeof plugin.card.new !== "boolean" || !Number.isSafeInteger(plugin.card.upvotes) || plugin.card.upvotes < 0 ||
          !Number.isSafeInteger(plugin.card.views) || plugin.card.views < 0 || typeof plugin.card.verified !== "boolean" ||
          (plugin.card.size_bytes !== null && (!Number.isSafeInteger(plugin.card.size_bytes) || plugin.card.size_bytes < 0)) ||
          plugin.card.verified !== (plugin.card.size_bytes !== null)) {
        throw new TypeError("Invalid search plugin")
      }

      if (plugin.id !== `${plugin.publisher}.${plugin.name}`) throw new TypeError("Invalid plugin identity")
      const expectedInstallCommand = `omarchy plugin add ${plugin.publisher}/${plugin.name}`
      if (plugin.install_command !== null && plugin.install_command !== expectedInstallCommand) {
        throw new TypeError("Invalid install command")
      }

      const pluginUrl = new URL(plugin.url, window.location.origin)
      if (!["http:", "https:"].includes(pluginUrl.protocol) || !pluginUrl.pathname.startsWith("/plugins/")) {
        throw new TypeError("Invalid search plugin URL")
      }

      let preview = null
      if (plugin.preview !== null) {
        if (!plugin.preview || typeof plugin.preview !== "object" || !plugin.preview.card ||
            typeof plugin.preview.card !== "object" || typeof plugin.preview.card.url !== "string") {
          throw new TypeError("Invalid search preview")
        }
        const previewUrl = new URL(plugin.preview.card.url, window.location.origin)
        if (!["http:", "https:"].includes(previewUrl.protocol) ||
            !previewUrl.pathname.startsWith("/rails/active_storage/")) {
          throw new TypeError("Invalid search preview URL")
        }
        preview = { ...plugin.preview, card: { ...plugin.preview.card, url: previewUrl.href } }
      }

      return this.pluginFromJson({ ...plugin, url: pluginUrl.href, preview })
    })

    return {
      page: page.number,
      perPage: page.per_page,
      total: page.total,
      more: page.more,
      query: query.q,
      sort: query.sort,
      category: query.category,
      tag: query.tag,
      plan,
      suggestions,
      plugins,
      categoryCounts,
      tagCounts,
      catalogRevision: data.catalog_revision
    }
  }

  pluginFromRow(row) {
    return {
      name: row.dataset.name,
      publisher: row.dataset.publisher,
      category: row.dataset.category,
      kinds: this.parseArray(row.dataset.kinds),
      tags: this.parseArray(row.dataset.tags),
      summary: row.dataset.summary,
      latestVersion: row.dataset.latestVersion || null,
      isNew: row.dataset.isNew === "true",
      upvotes: Number(row.dataset.upvotes || 0),
      views: Number(row.dataset.views || 0),
      downloads: Number(row.dataset.downloads || 0),
      verified: row.dataset.verified === "true",
      sizeBytes: row.dataset.sizeBytes ? Number(row.dataset.sizeBytes) : null,
      url: row.dataset.url,
      preview: row.dataset.previewUrl ? {
        url: row.dataset.previewUrl,
        width: Number(row.dataset.previewWidth || 0),
        height: Number(row.dataset.previewHeight || 0)
      } : null,
      installCommand: row.dataset.installCommand || null,
      match: { type: row.dataset.matchType, value: row.dataset.matchValue }
    }
  }

  pluginFromJson(plugin) {
    return {
      id: plugin.id,
      name: plugin.name,
      publisher: plugin.publisher,
      category: plugin.category || "other",
      kinds: plugin.kinds || [],
      tags: plugin.tags || [],
      summary: plugin.summary || "",
      latestVersion: plugin.latest_version,
      isNew: plugin.card.new,
      upvotes: plugin.card.upvotes,
      views: plugin.card.views,
      downloads: plugin.downloads,
      verified: plugin.card.verified,
      sizeBytes: plugin.card.size_bytes,
      url: this.localUrl(plugin.url),
      preview: plugin.preview?.card ? { ...plugin.preview.card, url: this.localUrl(plugin.preview.card.url) } : null,
      installCommand: plugin.install_command,
      match: plugin.match
    }
  }

  compactNumber(value) {
    return new Intl.NumberFormat("en", { notation: "compact", maximumSignificantDigits: 3 })
      .format(value).replace("K", "k")
  }

  formatBytes(value) {
    if (value < 1024) return `${value} B`
    const units = ["KB", "MB", "GB", "TB", "PB", "EB"]
    let amount = value
    let unit = "B"
    for (const nextUnit of units) {
      if (amount < 1024) break
      amount /= 1024
      unit = nextUnit
    }
    const number = new Intl.NumberFormat("en-US", { maximumSignificantDigits: 3, useGrouping: false }).format(amount)
    return `${number} ${unit}`
  }

  parseArray(value) {
    try {
      const parsed = JSON.parse(value || "[]")
      return Array.isArray(parsed) ? parsed : []
    } catch {
      return []
    }
  }

  localUrl(value) {
    try {
      const url = new URL(value, window.location.origin)
      if (!["http:", "https:"].includes(url.protocol)) return "/"
      return `${url.pathname}${url.search}${url.hash}`
    } catch {
      return "/"
    }
  }

  cancelPendingRequest() {
    window.clearTimeout(this.searchTimer)
    this.searchTimer = null
    this.requestGeneration += 1
    this.request?.abort()
    this.request = null
    this.pendingLoad = null
    this.queuedNavigation = null
    if (this.hasPickerTarget) this.pickerTarget.removeAttribute("aria-busy")
  }

  syncPickerState() {
    this.pickerTarget.dataset.indexPickerPageValue = this.page
    this.pickerTarget.dataset.indexPickerPerPageValue = this.perPage
    this.pickerTarget.dataset.indexPickerTotalValue = this.total
    this.pickerTarget.dataset.indexPickerMoreValue = this.more
    this.pickerTarget.dataset.indexPickerSelectedIndex = this.index
  }

  reloadedBrowseState() {
    const navigation = performance.getEntriesByType?.("navigation")?.[0]
    if (navigation?.type !== "reload") return null

    try {
      const serialized = window.sessionStorage.getItem(BROWSE_RELOAD_STORAGE_KEY)
      if (!serialized || serialized.length > 512) return null
      const stored = JSON.parse(serialized)
      const currentUrl = `${window.location.pathname}${window.location.search}`
      if (!stored || stored.url !== currentUrl || !stored.browse || typeof stored.browse !== "object") return null
      const perPage = Number(stored.browse.perPage)
      const absoluteAnchor = Number(stored.browse.absoluteAnchor)
      if (![COMPACT_WINDOW_SIZE, WINDOW_SIZE].includes(perPage) ||
          !Number.isSafeInteger(absoluteAnchor) || absoluteAnchor < 0 ||
          typeof stored.browse.selectionCleared !== "boolean") return null
      return { perPage, absoluteAnchor, selectionCleared: stored.browse.selectionCleared }
    } catch {
      return null
    }
  }

  persistBrowseReloadState(browse) {
    try {
      const url = `${window.location.pathname}${window.location.search}`
      window.sessionStorage.setItem(BROWSE_RELOAD_STORAGE_KEY, JSON.stringify({ url, browse }))
    } catch {
      // Storage is an optional enhancement; History remains authoritative in-session.
    }
  }

  updateHistory(mode) {
    const url = this.webUrl(this.page, this.loadedQuery)
    this.syncMobileSectionLinks(url)
    if (mode === "none") return
    if (url.href === window.location.href) {
      if (mode === "replace") this.replaceBrowseHistoryState()
      return
    }

    const turboHistory = window.Turbo?.navigator?.history
    if (turboHistory) {
      if (mode === "push") turboHistory.push(url)
      else turboHistory.replace(url, window.history.state?.turbo?.restorationIdentifier)
      this.replaceBrowseHistoryState()
      return
    }

    const method = mode === "push" ? "pushState" : "replaceState"
    const state = this.historyState(mode)
    window.history[method](state, "", url)
    this.persistBrowseReloadState(state.registryBrowse)
  }

  replaceBrowseHistoryState() {
    const state = this.historyState("replace")
    window.history.replaceState(state, "", window.location.href)
    this.persistBrowseReloadState(state.registryBrowse)
  }

  syncMobileSectionLinks(url = new URL(window.location.href)) {
    const base = `${url.pathname}${url.search}`
    document.querySelectorAll(".mobile-nav a[data-mobile-section]").forEach((link) => {
      const fragment = link.dataset.mobileSection === "home" ? "main-content" : link.dataset.mobileSection
      link.href = `${base}#${encodeURIComponent(fragment)}`
    })
  }

  historyState(mode) {
    const state = window.history.state || {}
    const registryBrowse = {
      perPage: this.perPage,
      absoluteAnchor: this.absoluteAnchor,
      selectionCleared: this.selectionCleared
    }
    if (mode !== "push" || !state.turbo) return { ...state, registryBrowse }
    const index = Number(state.turbo.restorationIndex)
    const identifier = globalThis.crypto?.randomUUID?.() || `${Date.now()}-${Math.random()}`
    return {
      ...state,
      registryBrowse,
      turbo: {
        ...state.turbo,
        restorationIdentifier: identifier,
        restorationIndex: Number.isSafeInteger(index) ? index + 1 : 0
      }
    }
  }

  expectedResponse(page, query, perPage = this.perPage || WINDOW_SIZE) {
    const params = new FormData(this.formTarget)
    const sort = params.get("sort") || "downloads"
    return {
      page,
      perPage,
      query,
      sort: SORTS.has(sort) ? sort : "downloads",
      category: params.get("category") || null,
      tag: params.get("tag") || null
    }
  }

  formParams(query = this.canonicalQuery(this.inputTarget.value)) {
    const params = new URLSearchParams(new FormData(this.formTarget))
    if (query) params.set("q", query)
    else params.delete("q")
    params.delete("page")
    params.delete("per_page")
    return params
  }

  apiUrl(page, query, perPage = this.perPage || WINDOW_SIZE) {
    const url = new URL(this.endpoint, window.location.origin)
    const params = this.formParams(query)
    params.set("page", page)
    params.set("per_page", perPage)
    url.search = params.toString()
    return url
  }

  syncFilterLinks() {
    [ "category", "tag" ].forEach((name) => {
      this.visibleCategoriesTarget.querySelectorAll(`a[data-${name}]`).forEach((link) => {
        link.href = this.filterUrl(name, link.dataset[name])
      })
    })
  }

  filterUrl(name, value) {
    const url = new URL(this.formTarget.action, window.location.origin)
    const params = this.formParams(this.canonicalQuery(this.inputTarget.value))
    if (params.get(name) === value) params.delete(name)
    else params.set(name, value)
    url.search = params.toString()
    return url
  }

  webUrl(page, query = this.canonicalQuery(this.inputTarget.value)) {
    const url = new URL(this.formTarget.action, window.location.origin)
    const params = this.formParams(query)
    if (page > 1) params.set("page", page)
    url.search = params.toString()
    return url
  }

  formSort() {
    return new FormData(this.formTarget).get("sort") || "downloads"
  }

  absoluteIndex(index) {
    return (this.page - 1) * this.perPage + index + 1
  }

  visitSelected() {
    this.rowTargets[this.index]?.querySelector(".index-picker__card-open")?.click()
  }

  enhanceShareLinks() {
    this.rowTargets.forEach((row) => {
      const share = row.querySelector(".index-picker__card-name")
      if (!share) return
      share.setAttribute("aria-label", share.dataset.shareLabel || "Copy plugin link")
      share.title = "Share plugin link"
    })
  }

  async sharePlugin(event) {
    if (event.type === "click" && (event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return
    if (event.type === "keydown" && (event.metaKey || event.ctrlKey || event.shiftKey || event.altKey)) return
    event.preventDefault()
    event.stopPropagation()
    const row = event.currentTarget.closest(".index-picker__row")
    if (!row) return

    const generation = ++this.copyGeneration
    const operation = beginClipboardOperation()
    try {
      const url = new URL(row.dataset.url, window.location.origin)
      if (url.origin !== window.location.origin) throw new TypeError("Plugin URL must stay on this registry")
      await copyText(url.href)
      if (!this.shareResultIsCurrent(generation, operation, row)) return
      this.showCopyStatus("Plugin link copied")
    } catch {
      if (!this.shareResultIsCurrent(generation, operation, row)) return
      this.showCopyStatus("Plugin link could not be copied")
    }
  }

  shareResultIsCurrent(generation, operation, row) {
    return clipboardOperationIsCurrent(operation) && this.element.isConnected &&
      generation === this.copyGeneration && row.isConnected &&
      this.rowTargets.includes(row)
  }

  async copySelected() {
    const selectedIndex = this.index
    const plugin = this.plugins[selectedIndex]
    const command = plugin?.installCommand
    if (!command) {
      beginClipboardOperation()
      this.showCopyStatus("Install command unavailable")
      return
    }
    const generation = ++this.copyGeneration
    const operation = beginClipboardOperation()

    try {
      await copyText(command)
      if (!this.copyResultIsCurrent(generation, operation, selectedIndex, plugin.id)) return
      this.showCopyStatus("Command copied")
    } catch {
      if (!this.copyResultIsCurrent(generation, operation, selectedIndex, plugin.id)) return
      this.showCopyStatus("Command could not be copied")
    }
  }

  copyResultIsCurrent(generation, operation, selectedIndex, pluginId) {
    return clipboardOperationIsCurrent(operation) && this.element.isConnected &&
      generation === this.copyGeneration && this.index === selectedIndex &&
      this.plugins[selectedIndex]?.id === pluginId
  }

  showCopyStatus(message) {
    if (!this.hasCopyStatusTarget) return
    window.clearTimeout(this.copyStatusTimer)
    this.copyStatusTarget.textContent = message
    this.copyStatusTarget.hidden = false
    this.copyStatusTarget.classList.remove("is-visible")
    requestAnimationFrame(() => this.copyStatusTarget.classList.add("is-visible"))
    this.copyStatusTimer = window.setTimeout(() => this.hideCopyStatus(), 2400)
  }


  hideCopyStatus() {
    if (!this.hasCopyStatusTarget) return
    this.copyGeneration += 1
    window.clearTimeout(this.copyStatusTimer)
    this.copyStatusTarget.classList.remove("is-visible")
    this.copyStatusTarget.hidden = true
  }
}

const STATUS_SELECTOR = ".index-picker__copy-status, .plugin-share__status"
let generation = 0

export function beginClipboardOperation() {
  generation += 1
  document.querySelectorAll(STATUS_SELECTOR).forEach((status) => {
    status.classList.remove("is-visible")
    status.hidden = true
  })
  return generation
}

export function clipboardOperationIsCurrent(token) {
  return token === generation
}

export function invalidateClipboardOperation(token) {
  if (token === generation) generation += 1
}

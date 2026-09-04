// Clipboard write with a selection-based fallback for engines that refuse
// the async API. Shared by the clipboard and readme-code controllers.
export async function copyText(text) {
  try {
    await navigator.clipboard.writeText(text)
    return true
  } catch (clipboardError) {
    const scratch = document.createElement("textarea")
    scratch.value = text
    scratch.setAttribute("readonly", "")
    scratch.style.position = "absolute"
    scratch.style.left = "-9999px"
    document.body.appendChild(scratch)

    try {
      scratch.select()
      if (!document.execCommand("copy")) throw new Error("Clipboard copy was rejected")
      return true
    } catch {
      throw clipboardError
    } finally {
      scratch.remove()
    }
  }
}

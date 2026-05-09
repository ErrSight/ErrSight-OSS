import { Controller } from "@hotwired/stimulus"

// Copies the AI "fix this error" prompt that is rendered inline (inside a
// <details> accordion) in the context aside. The prompt is built server-side
// (FixPromptBuilder) into the content target; the surrounding <details>
// handles expand/collapse natively, so this controller only copies the text
// and flashes a confirmation on the button.
export default class extends Controller {
  static targets = ["content", "copyButton", "status"]

  copy() {
    const text = this.contentTarget.textContent.trim()
    navigator.clipboard.writeText(text)
      .then(() => this.markCopied())
      .catch(() => { if (this.hasStatusTarget) this.statusTarget.textContent = "Copy failed" })
  }

  markCopied() {
    if (this.hasStatusTarget) this.statusTarget.textContent = "Copied to clipboard"
    if (!this.hasCopyButtonTarget) return

    const btn = this.copyButtonTarget
    const original = btn.dataset.label || btn.textContent
    btn.dataset.label = original
    btn.textContent = "Copied ✓"
    btn.classList.add("is-copied")
    if (this._revert) clearTimeout(this._revert)
    this._revert = setTimeout(() => {
      btn.textContent = original
      btn.classList.remove("is-copied")
      if (this.hasStatusTarget) this.statusTarget.textContent = ""
    }, 2000)
  }

  disconnect() {
    if (this._revert) clearTimeout(this._revert)
  }
}

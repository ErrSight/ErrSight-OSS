import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content", "button", "status"]

  copy() {
    const text = this.contentTarget.textContent.trim()
    navigator.clipboard.writeText(text).then(() => {
      const btn = this.hasButtonTarget ? this.buttonTarget : this.element.querySelector("button[data-action]")
      const original = btn.innerHTML
      // Keep an accessible name on the button while the check icon shows, and
      // announce success via the polite live region (WCAG 4.1.2 / 4.1.3).
      btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" class="h-4 w-4 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" /></svg>`
      btn.setAttribute("aria-label", "Copied")
      if (this.hasStatusTarget) this.statusTarget.textContent = "Copied to clipboard"
      setTimeout(() => {
        btn.innerHTML = original
        btn.removeAttribute("aria-label")
        if (this.hasStatusTarget) this.statusTarget.textContent = ""
      }, 2000)
    }).catch(() => {
      if (this.hasStatusTarget) this.statusTarget.textContent = "Copy failed"
    })
  }
}

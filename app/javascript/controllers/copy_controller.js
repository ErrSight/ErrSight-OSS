import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["content"]

  copy() {
    const text = this.contentTarget.textContent.trim()
    navigator.clipboard.writeText(text).then(() => {
      const btn = this.element.querySelector("button[data-action]")
      const original = btn.innerHTML
      btn.innerHTML = `<svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-green-400" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" /></svg>`
      setTimeout(() => { btn.innerHTML = original }, 2000)
    })
  }
}

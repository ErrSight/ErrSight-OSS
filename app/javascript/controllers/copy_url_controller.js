import { Controller } from "@hotwired/stimulus"

// Copies a URL to the clipboard on click. Reads from data-copy-url-value or
// data-copy-url attribute; falls back to window.location.href.
// Markup:
//   <button data-controller="copy-url" data-action="click->copy-url#copy"
//           data-copy-url-value="https://…">Copy</button>

export default class extends Controller {
  static values = { url: String }

  async copy(event) {
    event?.preventDefault?.()
    const btn = this.element
    const url = this.urlValue || btn.dataset.copyUrl || window.location.href
    const original = btn.innerHTML

    try {
      await navigator.clipboard.writeText(url)
    } catch (_err) {
      const ta = document.createElement("textarea")
      ta.value = url
      ta.style.position = "fixed"
      ta.style.opacity = "0"
      document.body.appendChild(ta)
      ta.select()
      try { document.execCommand("copy") } catch (_e) {}
      document.body.removeChild(ta)
    }

    btn.setAttribute("title", "Copied!")
    btn.innerHTML = '<span style="font-family: var(--mono); font-size: 11px;">✓</span>'
    setTimeout(() => {
      btn.innerHTML = original
      btn.setAttribute("title", "Copy link")
    }, 1400)
  }
}

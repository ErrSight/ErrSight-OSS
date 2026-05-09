import { Controller } from "@hotwired/stimulus"

// Renders the Cloudflare Turnstile widget into this element. Uses explicit
// rendering so the widget appears reliably after Turbo navigations (the
// auto-render mode only fires once on initial DOMContentLoaded).
//
// The widget injects a hidden <input name="cf-turnstile-response"> into the
// surrounding form when the challenge passes; the controller verifies that
// token server-side.

const SCRIPT_URL = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit"
let scriptPromise = null

function loadTurnstileScript() {
  scriptPromise ||= new Promise((resolve, reject) => {
    const existing = document.querySelector(`script[src^="${SCRIPT_URL.split("?")[0]}"]`)
    if (existing) {
      if (window.turnstile) { resolve(); return }
      existing.addEventListener("load", () => resolve())
      existing.addEventListener("error", reject)
      return
    }
    const script = document.createElement("script")
    script.src = SCRIPT_URL
    script.async = true
    script.defer = true
    script.onload = () => resolve()
    script.onerror = reject
    document.head.appendChild(script)
  })
  return scriptPromise
}

export default class extends Controller {
  static values = {
    siteKey: String,
    theme:   { type: String, default: "auto" }
  }

  connect() {
    loadTurnstileScript()
      .then(() => this.#renderWidget())
      .catch((e) => console.warn("Turnstile failed to load", e))
  }

  disconnect() {
    if (this.widgetId !== undefined && window.turnstile) {
      window.turnstile.remove(this.widgetId)
      this.widgetId = undefined
    }
  }

  #renderWidget() {
    if (!window.turnstile || !this.siteKeyValue) return
    this.widgetId = window.turnstile.render(this.element, {
      sitekey: this.siteKeyValue,
      theme:   this.themeValue
    })
  }
}

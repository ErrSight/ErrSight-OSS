import { Controller } from "@hotwired/stimulus"

// Query bar for the Items view. The canonical token string lives in the hidden
// `query` field; this controller edits it as chips are added/removed and submits
// the (GET) form to reload with the new filters. Also drives the live
// suggestions dropdown. Mirrors ItemsQuery::SUGGESTIONS on the server.
const SUGGESTIONS = [
  { key: "level",    values: ["error", "warning", "fatal", "info", "debug"], desc: "severity of the event" },
  { key: "is",       values: ["unresolved", "resolved", "muted", "ignored", "regression"], desc: "resolution status" },
  { key: "env",      values: ["production", "staging", "development"], desc: "deployment environment" },
  { key: "assigned", values: ["me", "none"], desc: "who owns it" },
  { key: "release",  values: [], desc: "build / version" },
  { key: "browser",  values: ["chrome", "safari", "firefox"], desc: "client browser" },
  { key: "has",      values: ["assignee", "link", "comments"], desc: "attribute present" }
]

export default class extends Controller {
  static targets = ["box", "query", "input", "suggest", "kbd"]

  connect() {
    this.outside = (e) => { if (!this.boxTarget.contains(e.target)) this.close() }
    document.addEventListener("click", this.outside)
  }

  disconnect() {
    document.removeEventListener("click", this.outside)
  }

  focus() {
    this.inputTarget.focus()
    this.open()
  }

  open() {
    this.boxTarget.classList.add("is-focus")
    this.render()
    this.suggestTarget.hidden = false
  }

  close() {
    this.boxTarget.classList.remove("is-focus")
    this.suggestTarget.hidden = true
  }

  typed() {
    this.render()
    this.suggestTarget.hidden = false
  }

  keydown(event) {
    if (event.key === "Enter") {
      event.preventDefault()
      const value = this.inputTarget.value.trim()
      if (value) { this.addToken(value) } else { this.element.requestSubmit() }
    } else if (event.key === "Backspace" && this.inputTarget.value === "") {
      const parts = this.tokens()
      if (parts.length) {
        event.preventDefault()
        parts.pop()
        this.queryTarget.value = parts.join(" ")
        this.element.requestSubmit()
      }
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  removeChip(event) {
    event.preventDefault()
    event.stopPropagation()
    const raw = event.currentTarget.dataset.raw
    this.queryTarget.value = this.tokens().filter((t) => t !== raw).join(" ")
    this.element.requestSubmit()
  }

  pick(event) {
    event.preventDefault()
    const token = event.currentTarget.dataset.token
    if (token.endsWith(":")) {
      this.inputTarget.value = token
      this.inputTarget.focus()
      this.render()
    } else {
      this.addToken(token)
    }
  }

  addToken(token) {
    const current = this.queryTarget.value.trim()
    this.queryTarget.value = current ? `${current} ${token}` : token
    this.element.requestSubmit()
  }

  tokens() {
    return this.queryTarget.value.split(/\s+/).filter(Boolean)
  }

  render() {
    const text = this.inputTarget.value.trim().toLowerCase()
    let label = "FILTER BY"
    let rows = []

    if (text.includes(":")) {
      label = "VALUES"
      const [key, valPart] = text.split(":")
      const match = SUGGESTIONS.find((s) => s.key === key) || SUGGESTIONS.find((s) => s.key.startsWith(key))
      if (match && match.values.length) {
        rows = match.values
          .filter((v) => !valPart || v.startsWith(valPart))
          .map((v) => ({ token: `${match.key}:${v}`, label: `${match.key}:${v}`, desc: match.desc }))
      } else if (match) {
        rows = [{ token: `${match.key}:`, label: `${match.key}:`, desc: match.desc }]
      }
    } else {
      rows = SUGGESTIONS
        .filter((s) => !text || s.key.startsWith(text))
        .map((s) => ({ token: `${s.key}:`, label: `${s.key}:`, desc: s.desc }))
    }

    const head = `<div class="es-qsuggest-label">${label}</div>`
    const body = rows.map((r) =>
      `<button type="button" class="es-qsuggest-row" data-action="items-query#pick" data-token="${r.token}">` +
      `<span class="es-qsuggest-key">${r.label}</span><span class="es-qsuggest-desc">${r.desc}</span></button>`
    ).join("")
    this.suggestTarget.innerHTML = body ? head + body : `<div class="es-qsuggest-label">No matches</div>`
  }
}

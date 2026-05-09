import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const LEVEL_BUCKET = {
  error: "err", fatal: "err",
  warning: "warn",
  info: "info",
  debug: "dbg"
}
const MAX_ROWS = 500

export default class extends Controller {
  static targets = ["list", "count", "search", "empty"]
  static values = { organizationId: String }

  connect() {
    this._filter = "all"
    this._query  = ""

    if (!this.organizationIdValue) return

    this._subscription = createConsumer().subscriptions.create(
      { channel: "DashboardEventsChannel", organization_id: this.organizationIdValue },
      { received: (data) => this._onReceived(data) }
    )

    this.element.querySelectorAll(".chip[data-filter]").forEach(chip => {
      chip.addEventListener("click", () => {
        this.element.querySelectorAll(".chip[data-filter]")
          .forEach(c => c.classList.toggle("active", c === chip))
        this._filter = chip.dataset.filter
        this._applyFilters()
      })
    })

    if (this.hasSearchTarget) {
      this.searchTarget.addEventListener("input", () => {
        this._query = this.searchTarget.value.trim().toLowerCase()
        this._applyFilters()
      })
    }
  }

  disconnect() {
    this._subscription?.unsubscribe()
  }

  // ── Private ──────────────────────────────────────────────────────────────

  _onReceived(data) {
    if (!data || !this.hasListTarget) return

    if (this.hasEmptyTarget) this.emptyTarget.remove()

    const row = this._buildRow(data)
    if (!row) return

    this.listTarget.prepend(row)
    this._trimRows()
    this._applyFilters()
  }

  // Mirrors the feed-row ERB in dashboard/index.html.erb.
  // Uses textContent exclusively so message/project_name can never inject markup.
  _buildRow(data) {
    const bucket = LEVEL_BUCKET[data.level] || "dbg"
    const msg    = (data.message || "").trim()
    const colon  = msg.indexOf(":")
    const head   = colon > -1 ? msg.slice(0, colon).trim() : msg
    const rest   = colon > -1 ? msg.slice(colon + 1).trim() : null

    const row = document.createElement("a")
    row.href        = data.url || "#"
    row.className   = "feed-row"
    row.dataset.level = bucket
    row.dataset.text  = msg.toLowerCase()

    const ts = document.createElement("div")
    ts.className  = "ts"
    ts.textContent = data.occurred_at || ""
    row.appendChild(ts)

    const lvlWrap  = document.createElement("div")
    const lvlBadge = document.createElement("span")
    lvlBadge.className  = `lvl ${bucket}`
    lvlBadge.textContent = (data.level || "").toUpperCase()
    lvlWrap.appendChild(lvlBadge)
    row.appendChild(lvlWrap)

    const txt      = document.createElement("div")
    txt.className  = "txt"
    const headSpan = document.createElement("span")
    headSpan.textContent = head
    txt.appendChild(headSpan)
    if (rest) {
      const dot = document.createElement("span")
      dot.className   = "dim"
      dot.textContent = " · "
      const restSpan  = document.createElement("span")
      restSpan.className   = "acc"
      restSpan.textContent = rest
      txt.appendChild(dot)
      txt.appendChild(restSpan)
    }
    row.appendChild(txt)

    const ctx  = document.createElement("div")
    ctx.className = "ctx"
    const proj = document.createElement("span")
    proj.className   = "proj"
    proj.textContent = data.project_name || ""
    ctx.appendChild(proj)
    if (data.environment) {
      const sep = document.createElement("span")
      sep.style.color  = "var(--fg-dimmer)"
      sep.textContent  = " · "
      ctx.appendChild(sep)
      ctx.appendChild(document.createTextNode(data.environment))
    }
    row.appendChild(ctx)

    const arrow = document.createElement("div")
    arrow.className   = "open"
    arrow.textContent = "→"
    row.appendChild(arrow)

    return row
  }

  _applyFilters() {
    if (!this.hasListTarget) return
    let visible = 0
    this.listTarget.querySelectorAll(".feed-row").forEach(row => {
      const show = (this._filter === "all" || row.dataset.level === this._filter) &&
                   (!this._query || (row.dataset.text || "").includes(this._query))
      row.style.display = show ? "" : "none"
      if (show) visible++
    })
    if (this.hasCountTarget) {
      this.countTarget.textContent = visible === 1 ? "1 event" : `${visible} events`
    }
  }

  _trimRows() {
    const rows = this.listTarget.querySelectorAll(".feed-row")
    for (let i = rows.length - 1; i >= MAX_ROWS; i--) rows[i].remove()
  }
}

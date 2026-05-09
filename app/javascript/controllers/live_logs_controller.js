import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

const MAX_ROWS = 1000
const SCROLL_TOP_THRESHOLD = 80

export default class extends Controller {
  static values = {
    projectId: Number,
    filterLevel: String,
    filterEnv: String,
    filterQ: String,
    paused: { type: Boolean, default: false }
  }

  static targets = ["logsList", "banner", "toggleBtn", "statusDot", "statusLabel"]

  connect() {
    this.pendingRows = []
    this.rowCount = this.hasLogsListTarget
      ? this.logsListTarget.querySelectorAll("[data-log-row]").length
      : 0

    this.subscription = createConsumer().subscriptions.create(
      { channel: "ProjectLogsChannel", project_id: this.projectIdValue },
      { received: (data) => this._onReceived(data) }
    )

    this._handleScroll = this._onScroll.bind(this)
    this._handleKeyDown = this._onKeyDown.bind(this)
    this._handleVisibility = this._onVisibilityChange.bind(this)

    window.addEventListener("scroll", this._handleScroll, { passive: true })
    document.addEventListener("keydown", this._handleKeyDown)
    document.addEventListener("visibilitychange", this._handleVisibility)
  }

  disconnect() {
    if (this.subscription) this.subscription.unsubscribe()
    window.removeEventListener("scroll", this._handleScroll)
    document.removeEventListener("keydown", this._handleKeyDown)
    document.removeEventListener("visibilitychange", this._handleVisibility)
  }

  // --- Actions ---

  togglePause() {
    this.pausedValue = !this.pausedValue
  }

  flushAndScrollTop() {
    if (!this.hasLogsListTarget) return

    // Prepend buffered rows oldest-first so newest ends up at top
    for (let i = this.pendingRows.length - 1; i >= 0; i--) {
      this._insertRow(this.pendingRows[i])
    }
    this.pendingRows = []
    this._hideBanner()
    window.scrollTo({ top: 0, behavior: "smooth" })
    this._trimRows()
  }

  // --- Stimulus callbacks ---

  pausedValueChanged() {
    if (!this.hasStatusDotTarget) return

    if (this.pausedValue) {
      this.statusDotTarget.className = "w-2 h-2 rounded-full bg-gray-500"
      this.statusLabelTarget.textContent = "PAUSED"
      this.statusLabelTarget.className = "text-gray-500"
    } else {
      this.statusDotTarget.className = "w-2 h-2 rounded-full bg-green-500 animate-pulse"
      this.statusLabelTarget.textContent = "LIVE"
      this.statusLabelTarget.className = "text-green-400"

      // Auto-flush if user is near top
      if (this._isAtTop() && this.pendingRows.length > 0) {
        this.flushAndScrollTop()
      }
    }
  }

  // --- Private ---

  _onReceived(data) {
    if (!data || !this.hasLogsListTarget) return

    if (this.filterLevelValue && data.level !== this.filterLevelValue) return
    if (this.filterEnvValue && data.environment !== this.filterEnvValue) return
    if (this.filterQValue && data.message &&
        !data.message.toLowerCase().includes(this.filterQValue.toLowerCase())) return

    const shouldBuffer = this.pausedValue ||
                         !this._isAtTop() ||
                         document.visibilityState === "hidden"

    if (shouldBuffer) {
      this.pendingRows.push(data)
      this._showBanner()
    } else {
      this._insertRow(data)
      this._trimRows()
    }
  }

  _insertRow(data) {
    const row = this._buildRow(data)
    if (!row) return

    const isError = data.level === "error" || data.level === "fatal"
    row.classList.add(isError ? "log-row--new-error" : "log-row--new")

    this.logsListTarget.prepend(row)
    this.rowCount++
  }

  // Mirrors app/views/events/_log_row.html.erb. Uses textContent everywhere
  // so user-controlled fields (message, email, full_path) can never inject markup.
  _buildRow(data) {
    if (!data.url) return null

    const row = document.createElement("a")
    row.href = data.url
    row.dataset.logRow = "true"
    row.className = "raw-row"
    row.style.gridTemplateColumns = "180px 60px 1fr 160px 160px"
    row.style.gap = "14px"
    row.style.padding = "8px 18px"

    const ts = document.createElement("span")
    ts.className = "ts"
    if (data.ts_main) {
      ts.appendChild(document.createTextNode(`${data.ts_main}.`))
      const ms = document.createElement("span")
      ms.style.color = "var(--fg-dimmer)"
      ms.textContent = data.ts_ms || ""
      ts.appendChild(ms)
    }
    row.appendChild(ts)

    const lvl = document.createElement("span")
    lvl.className = `lvl ${data.level || ""}`.trim()
    lvl.textContent = (data.level || "").toUpperCase()
    row.appendChild(lvl)

    const txt = document.createElement("span")
    txt.className = "txt"
    txt.appendChild(document.createTextNode(data.message || ""))
    if (data.request_id) {
      const reqId = document.createElement("span")
      reqId.className = "dim"
      reqId.textContent = ` · ${String(data.request_id).slice(0, 8)}`
      txt.appendChild(reqId)
    }
    row.appendChild(txt)

    const user = document.createElement("span")
    user.className = "user"
    if (data.email || data.user_id) {
      const acc = document.createElement("span")
      acc.className = "acc"
      acc.style.color = "var(--accent)"
      acc.textContent = data.email || `user#${data.user_id}`
      user.appendChild(acc)
    }
    row.appendChild(user)

    const loc = document.createElement("span")
    loc.className = "loc"
    if (data.full_path) loc.textContent = data.full_path
    row.appendChild(loc)

    return row
  }

  _trimRows() {
    if (this.rowCount <= MAX_ROWS) return

    const rows = this.logsListTarget.querySelectorAll("[data-log-row]")
    for (let i = rows.length - 1; i >= MAX_ROWS; i--) {
      rows[i].remove()
    }
    this.rowCount = MAX_ROWS
  }

  _isAtTop() {
    return window.scrollY < SCROLL_TOP_THRESHOLD
  }

  // --- Banner ---

  _showBanner() {
    if (this.hasBannerTarget) {
      this._updateBannerText()
      this.bannerTarget.classList.remove("hidden")
      return
    }

    const banner = document.createElement("div")
    banner.setAttribute("data-live-logs-target", "banner")
    banner.setAttribute("data-action", "click->live-logs#flushAndScrollTop")
    banner.className = "sticky top-0 z-10 bg-gray-800 border-b border-gray-700 text-teal-400 text-xs font-mono px-4 py-2 cursor-pointer text-center hover:bg-gray-750 transition"
    this.logsListTarget.prepend(banner)
    this._updateBannerText()
  }

  _updateBannerText() {
    if (!this.hasBannerTarget) return
    const count = this.pendingRows.length
    this.bannerTarget.textContent = `▲ ${count} new event${count > 1 ? "s" : ""} — click to jump to top`
  }

  _hideBanner() {
    if (this.hasBannerTarget) {
      this.bannerTarget.classList.add("hidden")
    }
  }

  // --- Event listeners ---

  _onScroll() {
    if (this._isAtTop() && this.pendingRows.length > 0 && !this.pausedValue) {
      this.flushAndScrollTop()
    }
  }

  _onKeyDown(e) {
    if (e.key !== "g" || e.metaKey || e.ctrlKey || e.altKey) return
    const tag = document.activeElement?.tagName
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return

    e.preventDefault()
    this.flushAndScrollTop()
  }

  _onVisibilityChange() {
    // When tab becomes visible again and user is at top, flush
    if (document.visibilityState === "visible" &&
        this._isAtTop() &&
        this.pendingRows.length > 0 &&
        !this.pausedValue) {
      this.flushAndScrollTop()
    }
  }
}

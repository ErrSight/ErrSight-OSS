import { Controller } from "@hotwired/stimulus"

const LEVEL_COLORS = {
  fatal:   "#991b1b",
  error:   "#CD5C5C",
  warning: "#b45309",
  info:    "#008080",
  debug:   "#7A5C3F"
}

export default class extends Controller {
  static targets = ["canvas", "total", "empty", "loading", "rangeSelect"]
  static values  = {
    url:         String,
    range:       { type: String, default: "24h" },
    fingerprint: String,
    environment: String
  }

  connect() {
    this.load()
  }

  selectRange(event) {
    this.rangeValue = event.target.value
    this.load()
  }

  async load() {
    if (!this.urlValue) return
    this._showLoading(true)
    try {
      const url = new URL(this.urlValue, window.location.origin)
      url.searchParams.set("range", this.rangeValue)
      if (this.fingerprintValue) url.searchParams.set("fingerprint", this.fingerprintValue)
      if (this.environmentValue) url.searchParams.set("environment", this.environmentValue)

      const response = await fetch(url.toString(), { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`status ${response.status}`)
      const data = await response.json()
      this._render(data)
    } catch (e) {
      console.warn("[time-series] load failed", e)
      this._showEmpty()
    } finally {
      this._showLoading(false)
    }
  }

  _render(data) {
    if (!this.hasCanvasTarget) return
    const buckets = data.buckets || []
    const total   = data.total || 0
    if (this.hasTotalTarget) this.totalTarget.textContent = total.toLocaleString()

    if (!buckets.length || total === 0) {
      this._showEmpty()
      this.canvasTarget.innerHTML = ""
      return
    }
    if (this.hasEmptyTarget) this.emptyTarget.classList.add("hidden")

    const width     = this.canvasTarget.clientWidth || 600
    const height    = 120
    const padX      = 4
    const padTop    = 8
    const padBottom = 20
    const plotW     = width - padX * 2
    const plotH    = height - padTop - padBottom
    const max       = Math.max(1, ...buckets.map(b => b.count))
    const barW      = plotW / buckets.length
    const levelOrder = ["debug", "info", "warning", "error", "fatal"]

    const bars = buckets.map((b, i) => {
      const x = padX + i * barW
      let yCursor = padTop + plotH
      const segments = levelOrder
        .map(level => ({ level, count: b.by_level[level] || 0 }))
        .filter(s => s.count > 0)
        .map(s => {
          const h = (s.count / max) * plotH
          const y = yCursor - h
          yCursor = y
          return `<rect x="${x + 1}" y="${y.toFixed(1)}" width="${Math.max(0, barW - 2).toFixed(1)}" height="${h.toFixed(1)}" fill="${LEVEL_COLORS[s.level] || "#7A5C3F"}" rx="1"></rect>`
        })
      const title = `<title>${b.label} — ${b.count} event${b.count === 1 ? "" : "s"}</title>`
      return `<g>${segments.join("")}${title}</g>`
    }).join("")

    const labels = []
    const stride = Math.max(1, Math.ceil(buckets.length / 6))
    buckets.forEach((b, i) => {
      if (i % stride !== 0 && i !== buckets.length - 1) return
      const x = padX + i * barW + barW / 2
      labels.push(`<text x="${x.toFixed(1)}" y="${(height - 4).toFixed(1)}" text-anchor="middle" font-size="10" fill="#7A5C3F">${b.label}</text>`)
    })

    this.canvasTarget.innerHTML = `
      <svg viewBox="0 0 ${width} ${height}" width="100%" height="${height}" preserveAspectRatio="none" role="img" aria-label="Events over time">
        ${bars}
        ${labels.join("")}
      </svg>
    `
  }

  _showEmpty() {
    if (this.hasEmptyTarget) this.emptyTarget.classList.remove("hidden")
  }

  _showLoading(on) {
    if (!this.hasLoadingTarget) return
    this.loadingTarget.classList.toggle("hidden", !on)
  }
}

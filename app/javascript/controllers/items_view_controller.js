import { Controller } from "@hotwired/stimulus"

// Presentation-only Items view preferences (density + zebra rows), persisted to
// a cookie and applied to <body> as data attributes. No server round-trip.
export default class extends Controller {
  static targets = ["cozy", "dense", "zebra"]

  connect() {
    this.applyDensity(this._get("items_density") || document.body.getAttribute("data-density") || "comfortable", false)
    this.applyZebra(this._get("items_zebra") === "true", false)
  }

  cozy() { this.applyDensity("comfortable") }
  dense() { this.applyDensity("compact") }
  toggleZebra() { this.applyZebra(document.body.getAttribute("data-items-zebra") !== "true") }

  applyDensity(value, persist = true) {
    document.body.setAttribute("data-density", value)
    if (this.hasCozyTarget) this.cozyTarget.classList.toggle("on", value === "comfortable")
    if (this.hasDenseTarget) this.denseTarget.classList.toggle("on", value === "compact")
    if (persist) this._set("items_density", value)
  }

  applyZebra(on, persist = true) {
    document.body.setAttribute("data-items-zebra", on ? "true" : "false")
    if (this.hasZebraTarget) this.zebraTarget.classList.toggle("is-on", on)
    if (persist) this._set("items_zebra", on ? "true" : "false")
  }

  _get(name) {
    const match = document.cookie.split("; ").find((row) => row.startsWith(`${name}=`))
    return match ? match.split("=")[1] : null
  }

  _set(name, value) {
    document.cookie = `${name}=${value}; path=/; max-age=31536000; samesite=lax`
  }
}

import { Controller } from "@hotwired/stimulus"

// Responsive <details> disclosure: open and always-visible on desktop, collapsed
// by default on phones/tablets so a long list (docs TOC, filter facets) doesn't
// push content down. The element renders with `open` so desktop has no flash;
// we close it below the `max` breakpoint at connect and on viewport change.
//   data-controller="disclosure" data-disclosure-max-value="900"
export default class extends Controller {
  static values = { max: { type: Number, default: 960 } }

  connect() {
    this._mq = window.matchMedia(`(max-width: ${this.maxValue}px)`)
    this._sync = () => { this.element.open = !this._mq.matches }
    this._sync()
    this._mq.addEventListener("change", this._sync)
  }

  disconnect() {
    if (this._mq) this._mq.removeEventListener("change", this._sync)
  }
}

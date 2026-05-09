import { Controller } from "@hotwired/stimulus"

// Handles the tab bar on the event show page.
// Markup:
//   <div data-controller="ev-tabs">
//     <button class="tab" data-tab="stack" data-action="click->ev-tabs#show">Stack</button>
//     ...
//     <div data-ev-tab-pane="stack">…</div>
//     <div data-ev-tab-pane="raw" hidden>…</div>
//   </div>

export default class extends Controller {
  connect() {
    // Wire clicks even if data-action isn't present (legacy markup).
    this._tabs().forEach(t => {
      if (!t.dataset.evTabsBound) {
        t.dataset.evTabsBound = "1"
        t.addEventListener("click", e => this.show(e))
      }
    })
    // Default to first tab marked .active, else first tab.
    const active = this._tabs().find(t => t.classList.contains("active")) || this._tabs()[0]
    if (active) this._apply(active.dataset.tab)
  }

  show(event) {
    event.preventDefault()
    const btn = event.currentTarget
    this._apply(btn.dataset.tab)
  }

  _apply(name) {
    if (!name) return
    this._tabs().forEach(t => t.classList.toggle("active", t.dataset.tab === name))
    this._panes().forEach(p => { p.hidden = (p.dataset.evTabPane !== name) })
  }

  _tabs() {
    return Array.from(this.element.querySelectorAll(".tab[data-tab]"))
  }
  _panes() {
    return Array.from(this.element.querySelectorAll("[data-ev-tab-pane]"))
  }
}

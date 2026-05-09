import { Controller } from "@hotwired/stimulus"

// Toggles between "in-app only" and "full trace" on the stack-frame list.
// Markup:
//   <div class="right" data-controller="stack-filter">
//     <a data-stack-mode="inapp" data-action="click->stack-filter#set">in-app</a>
//     <a data-stack-mode="full" class="active" data-action="click->stack-filter#set">full</a>
//   </div>
//   <div data-stack-filter-target="list">
//     <div class="stack-frame frame-in-app">…</div>
//     <div class="stack-frame frame-ext">…</div>
//   </div>
//
// The list lives outside this controller (next to the .right toolbar),
// so we look for it on the nearest tab pane / panel.

export default class extends Controller {
  static targets = ["list"]

  connect() {
    const active = this.element.querySelector('[data-stack-mode].active') ||
                   this.element.querySelector('[data-stack-mode]')
    if (active) this._apply(active.dataset.stackMode, active)
  }

  set(event) {
    event.preventDefault()
    const btn = event.currentTarget
    this._apply(btn.dataset.stackMode, btn)
  }

  _apply(mode, activeBtn) {
    this.element.querySelectorAll('[data-stack-mode]').forEach(b => {
      b.classList.toggle("active", b === activeBtn)
    })
    const list = this._list()
    if (!list) return
    list.querySelectorAll(".stack-frame").forEach(f => {
      f.style.display = (mode === "inapp" && f.classList.contains("frame-ext")) ? "none" : ""
    })
  }

  _list() {
    if (this.hasListTarget) return this.listTarget
    const pane = this.element.closest('[data-ev-tab-pane="stack"]') || this.element.closest(".panel")
    return pane ? pane.querySelector('[data-stack-filter-target="list"]') : null
  }
}

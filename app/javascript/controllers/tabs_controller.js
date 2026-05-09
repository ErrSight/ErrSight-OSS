import { Controller } from "@hotwired/stimulus"

// Usage:
//   <div data-controller="tabs" data-tabs-active-value="ruby">
//     <button class="tab" data-tabs-target="tab" data-tab="ruby"  data-action="click->tabs#show">Ruby</button>
//     <button class="tab" data-tabs-target="tab" data-tab="react" data-action="click->tabs#show">React</button>
//     <div data-tabs-target="panel" data-tab="ruby">…</div>
//     <div data-tabs-target="panel" data-tab="react" class="hidden">…</div>
//   </div>

export default class extends Controller {
  static targets = ["tab", "panel"]
  static values  = { active: String }

  connect() {
    this._apply(this.activeValue || this.tabTargets[0]?.dataset.tab)
  }

  show(event) {
    event.preventDefault()
    this._apply(event.currentTarget.dataset.tab)
  }

  _apply(name) {
    this.activeValue = name

    this.tabTargets.forEach(tab => {
      tab.classList.toggle("active", tab.dataset.tab === name)
    })

    this.panelTargets.forEach(panel => {
      panel.classList.toggle("hidden", panel.dataset.tab !== name)
    })
  }
}

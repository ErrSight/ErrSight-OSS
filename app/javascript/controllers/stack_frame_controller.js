import { Controller } from "@hotwired/stimulus"

// Toggles the expanded state of a single .stack-frame when its .frame-head is clicked.
// Attach on the .stack-frame element:
//   <div class="stack-frame" data-controller="stack-frame">
//     <div class="frame-head" data-action="click->stack-frame#toggle">…</div>
//   </div>

export default class extends Controller {
  toggle(event) {
    event.preventDefault()
    this.element.classList.toggle("open")
  }
}

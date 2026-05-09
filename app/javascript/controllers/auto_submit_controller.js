import { Controller } from "@hotwired/stimulus"

// Submits the parent form whenever any element with
// `data-action="change->auto-submit#submit"` (or input/...) fires the action.
// Replaces inline onchange="this.form.requestSubmit()" handlers, which our
// CSP (script-src 'self' + nonce) blocks: nonces don't cover inline event
// attributes, so those handlers silently never fire.
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}

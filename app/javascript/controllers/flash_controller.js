import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { timeout: { type: Number, default: 5000 } }

  connect() {
    if (this.timeoutValue > 0) {
      this.timer = setTimeout(() => this.dismiss(), this.timeoutValue)
    }
  }

  dismiss() {
    this.element.style.transition = "opacity 0.3s ease"
    this.element.style.opacity = "0"
    setTimeout(() => this.element.remove(), 300)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}

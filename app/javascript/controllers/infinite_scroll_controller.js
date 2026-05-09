import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }
  static targets = ["spinner"]

  connect() {
    this.loading = false
    this.observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && !this.loading) {
          this.loadMore()
        }
      },
      { rootMargin: "300px" }
    )
    this.observer.observe(this.element)
  }

  disconnect() {
    this.observer?.disconnect()
  }

  async loadMore() {
    this.loading = true
    this.observer.disconnect()

    if (this.hasSpinnerTarget) {
      this.spinnerTarget.classList.remove("hidden")
    }

    try {
      const response = await fetch(this.urlValue, {
        headers: {
          "X-Requested-With": "XMLHttpRequest",
          "Accept": "text/html"
        }
      })

      if (!response.ok) {
        this.element.remove()
        return
      }

      const html = await response.text()
      const doc = new DOMParser().parseFromString(html, "text/html")
      const list = document.getElementById("logs-list")

      // Append new rows
      doc.querySelectorAll("[data-log-row]").forEach(row => {
        list.appendChild(document.adoptNode(row))
      })

      // Hand off to the next sentinel (or remove if last page)
      const nextSentinel = doc.querySelector("[data-controller='infinite-scroll']")
      if (nextSentinel) {
        this.element.replaceWith(document.adoptNode(nextSentinel))
      } else {
        this.element.remove()
      }
    } catch (e) {
      console.error("[InfiniteScroll] fetch failed:", e)
      this.loading = false
    }
  }
}

import { Controller } from "@hotwired/stimulus"

// Slide-in issue-detail overlay.
//
// Issue rows in the list target the #issue-overlay Turbo Frame
// (data-turbo-frame). When the frame finishes loading we reveal the panel.
// Closing (backdrop click, the close button, or Escape) hides the panel and
// clears the frame so the same issue re-loads fresh next time it is opened.
export default class extends Controller {
  static targets = ["frame"]

  opened() {
    // turbo:frame-load also fires on an empty initial frame; only open once
    // there is real content to show.
    if (this.hasFrameTarget && this.frameTarget.children.length === 0) return
    this.element.classList.add("is-open")
    document.body.style.overflow = "hidden"
  }

  close(event) {
    if (event) event.preventDefault()
    if (!this.element.classList.contains("is-open")) return
    this.element.classList.remove("is-open")
    document.body.style.overflow = ""
    if (this.hasFrameTarget) {
      this.frameTarget.removeAttribute("src")
      this.frameTarget.removeAttribute("complete")
      this.frameTarget.innerHTML = ""
    }
  }

  keydown(event) {
    if (event.key === "Escape") this.close(event)
  }
}

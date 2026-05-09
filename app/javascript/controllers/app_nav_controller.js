import { Controller } from "@hotwired/stimulus"

// Off-canvas app sidebar drawer (<=900px). Desktop is pure grid CSS; this only
// runs the open/close state on phones/tablets. Toggles `nav-open` on the
// .design-shell. Auto-registered by eagerLoadControllersFrom in
// controllers/index.js.
export default class extends Controller {
  static targets = ["toggle", "backdrop"]

  connect() {
    // Clear the drawer (and any stuck body scroll-lock) when the viewport grows
    // past the drawer breakpoint, mirroring disclosure_controller.
    this._mq = window.matchMedia("(min-width: 901px)")
    this._onDesktop = () => { if (this._mq.matches) this.close() }
    this._mq.addEventListener("change", this._onDesktop)
  }

  get isOpen() {
    return this.element.classList.contains("nav-open")
  }

  toggle(e) {
    e.stopPropagation()
    this.isOpen ? this.close() : this.open()
  }

  open() {
    this._lastFocused = document.activeElement
    this.element.classList.add("nav-open")
    this.toggleTarget.setAttribute("aria-expanded", "true")
    this.toggleTarget.setAttribute("aria-label", "Close menu")
    document.body.style.overflow = "hidden"
    const sidebar = document.getElementById("appSidebar")
    const first = sidebar && sidebar.querySelector("a, button")
    if (first) first.focus()
  }

  close() {
    if (!this.isOpen) return
    this.element.classList.remove("nav-open")
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.toggleTarget.setAttribute("aria-label", "Open menu")
    document.body.style.removeProperty("overflow")
    // Restore focus to the trigger (a no-op once a nav tap replaces the page).
    if (this._lastFocused && document.contains(this._lastFocused)) {
      this._lastFocused.focus()
    } else {
      this.toggleTarget.focus()
    }
  }

  onKeydown(e) {
    if (e.key === "Escape" && this.isOpen) this.close()
  }

  // Close when a real navigation link/button inside the drawer is tapped, but
  // leave the org/project switcher popover toggles alone so they open in-drawer.
  closeOnNav(e) {
    if (e.target.closest("[data-action*='dropdown#toggle']")) return
    if (e.target.closest("a, button[type='submit'], .sb-popover-row, .sb-popover-action")) {
      this.close()
    }
  }

  disconnect() {
    if (this._mq) this._mq.removeEventListener("change", this._onDesktop)
    document.body.style.removeProperty("overflow")
  }
}

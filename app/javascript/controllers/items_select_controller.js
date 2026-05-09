import { Controller } from "@hotwired/stimulus"

// Bulk row selection for the Issues table. Tracks selected fingerprints, toggles
// the floating bulk bar, and POSTs the chosen action to /events/bulk.
export default class extends Controller {
  static targets = ["all", "bar", "count"]
  static values = { mode: String, bulkUrl: String }

  connect() {
    this.selected = new Set()
  }

  toggle(event) {
    event.preventDefault()
    event.stopPropagation()
    const cell = event.currentTarget
    const id = event.params.id
    if (!id) return
    if (this.selected.has(id)) {
      this.selected.delete(id)
      this._mark(cell, false)
    } else {
      this.selected.add(id)
      this._mark(cell, true)
    }
    this.refresh()
  }

  toggleAll(event) {
    event.preventDefault()
    event.stopPropagation()
    const cells = this._cells()
    const turnOn = this.selected.size < cells.length
    this.selected.clear()
    cells.forEach((cell) => {
      const id = cell.getAttribute("data-items-select-id-param")
      if (turnOn && id) this.selected.add(id)
      this._mark(cell, turnOn)
    })
    this.refresh()
  }

  keyToggle(event) {
    if (event.key !== "Enter" && event.key !== " ") return
    event.preventDefault()
    if (event.currentTarget.dataset.itemsSelectIdParam) {
      this.toggle(event)
    } else {
      this.toggleAll(event)
    }
  }

  clear() {
    this.selected.clear()
    this._cells().forEach((cell) => this._mark(cell, false))
    this.refresh()
  }

  act(event) {
    this._submit(event.currentTarget.dataset.bulkAction)
  }

  // Assign menu item: POSTs action_type=assign plus the chosen assignee_id
  // (empty string = unassign). The page reloads on submit, so the open
  // <details> menu resets on its own.
  assign(event) {
    const assigneeId = event.params.assigneeId
    this._submit("assign", { assignee_id: assigneeId == null ? "" : String(assigneeId) })
  }

  _submit(action, extra = {}) {
    if (this.selected.size === 0 || !this.bulkUrlValue) return

    const form = document.createElement("form")
    form.method = "post"
    form.action = this.bulkUrlValue
    form.style.display = "none"

    const add = (name, value) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    }

    const token = document.querySelector("meta[name='csrf-token']")
    if (token) add("authenticity_token", token.content)
    add("action_type", action)
    Object.entries(extra).forEach(([name, value]) => add(name, value))
    this.selected.forEach((id) => add("fingerprints[]", id))

    document.body.appendChild(form)
    if (form.requestSubmit) { form.requestSubmit() } else { form.submit() }
  }

  refresh() {
    const n = this.selected.size
    if (this.hasBarTarget) this.barTarget.hidden = n === 0
    if (this.hasCountTarget) this.countTarget.textContent = n
    if (this.hasAllTarget) {
      const total = this._cells().length
      this.allTarget.classList.toggle("on", n > 0 && n === total)
    }
  }

  _cells() {
    return Array.from(this.element.querySelectorAll("[data-items-select-id-param]"))
  }

  _mark(cell, on) {
    const check = cell.querySelector(".es-check")
    const row = cell.closest(".iss-row")
    if (check) check.classList.toggle("on", on)
    cell.setAttribute("aria-checked", on ? "true" : "false")
    if (row) row.classList.toggle("is-selected", on)
  }
}

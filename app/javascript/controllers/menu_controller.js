import { Controller } from "@hotwired/stimulus"

// Toggles the mobile dropdown panel for the floating nav bars (end-user topbar
// + admin nav). The inline nav is shown at the breakpoint and up; below it the
// links collapse behind a hamburger that reveals this panel. Closes on
// outside-click and Escape; a Turbo navigation re-renders the partial, so the
// panel naturally starts closed again on the next page.
export default class extends Controller {
  static targets = ["panel", "button"]

  connect() {
    this.onDocClick = this.onDocClick.bind(this)
    this.onKeydown = this.onKeydown.bind(this)
  }

  disconnect() {
    this.stopListening()
  }

  toggle(event) {
    event.preventDefault()
    this.panelTarget.classList.contains("hidden") ? this.open() : this.close()
  }

  open() {
    this.panelTarget.classList.remove("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.onDocClick)
    document.addEventListener("keydown", this.onKeydown)
  }

  close() {
    this.panelTarget.classList.add("hidden")
    if (this.hasButtonTarget) this.buttonTarget.setAttribute("aria-expanded", "false")
    this.stopListening()
  }

  onDocClick(event) {
    if (!this.element.contains(event.target)) this.close()
  }

  onKeydown(event) {
    if (event.key === "Escape") this.close()
  }

  stopListening() {
    document.removeEventListener("click", this.onDocClick)
    document.removeEventListener("keydown", this.onKeydown)
  }
}

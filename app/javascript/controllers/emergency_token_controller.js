import { Controller } from "@hotwired/stimulus"

// Moves the emergency token from the URL fragment into the form, then erases it from
// the address bar and history. The fragment is never sent to the server; the form
// POSTs it only when the operator clicks — never automatically, so link scanners that
// run JavaScript still cannot redeem it.
export default class extends Controller {
  static targets = ["input", "manual", "detected"]

  connect() {
    const token = window.location.hash.slice(1)
    if (!token) return

    this.inputTarget.value = token
    history.replaceState(null, "", window.location.pathname + window.location.search)
    this.manualTarget.classList.add("hidden")
    this.detectedTarget.classList.remove("hidden")
  }
}

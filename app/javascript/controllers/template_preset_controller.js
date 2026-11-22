import { Controller } from "@hotwired/stimulus"

// Fills the messenger body template from a preset. The presets are only starting
// points — the operator edits the result freely, and the server validates it.
export default class extends Controller {
  static targets = ["template"]
  static values = { presets: Object }

  apply(event) {
    const template = this.presetsValue[event.target.value]
    if (template === undefined) return
    this.templateTarget.value = template
  }
}

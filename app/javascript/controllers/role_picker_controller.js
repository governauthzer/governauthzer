import { Controller } from "@hotwired/stimulus"

// Two dependent, searchable fields for the access-request form: pick an
// application, then one of its roles. Roles are scoped to the chosen application
// (role names are not globally unique), and selecting a role fills the hidden
// role_id the controller submits.
export default class extends Controller {
  static targets = ["app", "role", "roleList", "roleId", "submit"]
  static values = { roles: Array }

  connect() {
    this.disableRole()
  }

  appChanged() {
    const roles = this.rolesForApp(this.appTarget.value)
    this.roleListTarget.replaceChildren(
      ...roles.map((role) => {
        const option = document.createElement("option")
        option.value = role.name
        return option
      })
    )
    this.roleTarget.value = ""
    this.roleTarget.disabled = roles.length === 0
    this.roleTarget.placeholder = roles.length ? "Search roles…" : "No roles for this application"
    this.setRole(null)
  }

  roleChanged() {
    const match = this.rolesForApp(this.appTarget.value).find(
      (role) => role.name === this.roleTarget.value
    )
    this.setRole(match || null)
  }

  rolesForApp(appName) {
    const name = (appName || "").trim()
    return this.rolesValue.filter((role) => role.app === name)
  }

  setRole(role) {
    this.roleIdTarget.value = role ? role.id : ""
    this.submitTarget.disabled = !role
  }

  disableRole() {
    this.roleTarget.disabled = true
    this.setRole(null)
  }
}

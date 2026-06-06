# Human-readable flash text for the Result codes the access services and policies
# return, so the end-user UI controllers don't each reinvent the mapping.
module AccessFlashMessages
  MESSAGES = {
    access_already_exists: "You already hold or have requested this role.",
    role_protected: "This role can't be requested — it's assigned by an administrator.",
    no_eligible_approver: "No approver is configured for this role — contact an administrator.",
    not_current_approver: "This request is not awaiting your approval.",
    not_requester: "You can only withdraw your own requests.",
    not_pending: "This request is no longer pending."
  }.freeze

  private

  def access_flash(code)
    MESSAGES[code] || "That action could not be completed."
  end
end

module Api::ServiceFailureRendering
  extend ActiveSupport::Concern

  ERROR_MAPPING = {
    unknown_auth_provider_slug: {
      status: :unprocessable_content,
      code: "unknown_auth_provider_slug",
      message: "Unknown auth_provider_slug."
    },
    external_id_collision: {
      status: :conflict,
      code: "external_id_collision",
      message: "External identity already linked to another user."
    },
    omniauth_identity_collision: {
      status: :conflict,
      code: "omniauth_identity_collision",
      message: "OmniAuth identity already linked to another user."
    },
    reactivation_required: {
      status: :unprocessable_content,
      code: "reactivation_required",
      message: "User is terminated; reactivation requires the explicit reactivation flow."
    },
    external_identity_not_found: {
      status: :not_found,
      code: "external_identity_not_found",
      message: "No user found for the given (source, external_id)."
    },
    conflicting_manager_ref: {
      status: :unprocessable_content,
      code: "conflicting_manager_ref",
      message: "Cannot set both manager_id and manager_external_id in the same request."
    },
    manager_not_found: {
      status: :unprocessable_content,
      code: "manager_not_found",
      message: "No user found for the given manager_external_id."
    }
  }.freeze

  def render_service_failure(result)
    spec = ERROR_MAPPING.fetch(result.code) do
      raise ArgumentError, "Unmapped service failure code: #{result.code.inspect}"
    end
    render_error(
      code: spec[:code],
      status: spec[:status],
      message: spec[:message],
      details: result.context
    )
  end
end

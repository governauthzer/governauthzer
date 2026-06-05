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
    },
    # --- Snapshot sync ---
    count_mismatch: {
      status: :bad_request,
      code: "count_mismatch",
      message: "expected_count differs from users.size by more than 5%."
    },
    terminated_in_snapshot: {
      status: :bad_request,
      code: "terminated_in_snapshot",
      message: "Snapshots express termination by absence; 'terminated' status is not allowed in the payload."
    },
    as_of_in_future: {
      status: :bad_request,
      code: "as_of_in_future",
      message: "as_of is missing, unparseable, or too far in the future (clock-skew guard)."
    },
    validation_failed: {
      status: :unprocessable_content,
      code: "validation_failed",
      message: "One or more users in the snapshot failed validation."
    },
    stale_snapshot: {
      status: :conflict,
      code: "stale_snapshot",
      message: "as_of is older than the last applied snapshot for this source."
    },
    duplicate_snapshot: {
      status: :conflict,
      code: "duplicate_snapshot",
      message: "A snapshot with this as_of and identical payload was already applied."
    },
    conflicting_snapshot: {
      status: :conflict,
      code: "conflicting_snapshot",
      message: "A snapshot with this as_of but different payload was already applied."
    },
    mass_termination_blocked: {
      status: :unprocessable_content,
      code: "mass_termination_blocked",
      message: "Computed orphans exceed the safety threshold; resend with override_circuit_breaker=true to proceed."
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

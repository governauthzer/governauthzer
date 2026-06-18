module ApplicationHelper
  def input_class
    "input"
  end

  # A calm dot-chip: neutral chip + a single semantic dot. Keeps the monochrome
  # brand while making status scannable. Works for User and Access states.
  def status_pill(status)
    dot = case status
    when "active", "approved" then "bg-emerald-500"
    when "suspended"          then "bg-amber-500"
    when "orphaned"           then "bg-orange-500"
    when "terminated"         then "bg-red-500"
    else "bg-gray-400" # pending, pending_start, unknown
    end
    tag.span(class: "pill bg-gray-100 text-gray-700") do
      safe_join([ tag.span("", class: "w-1.5 h-1.5 rounded-full #{dot}"), status.humanize ])
    end
  end

  # Provisioning state of a grant, shown only when a provisioner is in play
  # (nil for not_required → the view renders nothing, keeping standalone-core
  # installs uncluttered).
  def provisioning_pill(provisioning_status)
    return if provisioning_status == "not_required"

    dot = case provisioning_status
    when "applied" then "bg-emerald-500"
    when "failed"  then "bg-red-500"
    else "bg-amber-500" # pending
    end
    tag.span(class: "pill bg-gray-100 text-gray-700") do
      safe_join([ tag.span("", class: "w-1.5 h-1.5 rounded-full #{dot}"), provisioning_status.humanize ])
    end
  end

  def claim_mappings_value(auth_provider)
    # Prefer the unparsed textarea string after a failed submit, so the operator's
    # invalid input is preserved for correction. Otherwise pretty-print the stored value.
    return auth_provider.claim_mappings_raw if auth_provider.claim_mappings_raw
    case auth_provider.claim_mappings
    when Array, Hash then JSON.pretty_generate(auth_provider.claim_mappings)
    else "[]"
    end
  end
end

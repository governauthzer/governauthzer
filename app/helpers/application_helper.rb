module ApplicationHelper
  def input_class
    "w-full border border-gray-300 rounded px-3 py-2 text-sm focus:outline-none focus:border-gray-900"
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

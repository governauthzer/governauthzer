module Users
  module ManagerReferenceResolver
    # Resolves manager_external_id (from request body) into a concrete manager_id
    # for assignment. Mutually exclusive with manager_id in attrs.
    #
    # Returns [resolved_attrs, failure_result_or_nil].
    #
    # - manager_external_id is ApplicationService::NOT_PROVIDED → no change (caller didn't pass the field)
    # - both manager_id and manager_external_id present in body → failure(:conflicting_manager_ref)
    # - manager_external_id is nil → clears manager (manager_id => nil)
    # - manager_external_id is {source, external_id} → looks up; sets manager_id or fails (:manager_not_found)
    def resolve_manager_reference(attrs, manager_external_id)
      return [ attrs, nil ] if manager_external_id.equal?(ApplicationService::NOT_PROVIDED)

      if attrs.key?(:manager_id)
        return [ attrs, failure(:conflicting_manager_ref) ]
      end

      if manager_external_id.nil?
        return [ attrs.merge(manager_id: nil), nil ]
      end

      source = (manager_external_id[:source] || manager_external_id["source"]).to_s
      ext_id = (manager_external_id[:external_id] || manager_external_id["external_id"]).to_s

      if source.blank? || ext_id.blank?
        return [ attrs, failure(:manager_not_found, source: source, external_id: ext_id) ]
      end

      identity = ExternalIdentity.find_by(
        source: ExternalIdentity.normalize_source(source),
        external_id: ext_id
      )

      if identity.nil?
        return [ attrs, failure(:manager_not_found, source: source, external_id: ext_id) ]
      end

      [ attrs.merge(manager_id: identity.user_id), nil ]
    end
  end
end

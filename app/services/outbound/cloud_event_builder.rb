module Outbound
  # Projects a published AuditEvent into a CloudEvent (CNCF spec v1.0) hash.
  #
  # Versioning (decided 2026-06-16): the event KIND lives in `type` (stable
  # forever); the payload SHAPE version lives in `dataschema` (a version-pinned
  # canonical URL). Additive `data` changes never bump the version — only a
  # breaking change gets a new dataschema URL. `specversion` is the CloudEvents
  # spec itself (1.0), a separate axis we do not version.
  #
  # The outbound contract is ACCESS-GRAIN ONLY: two actionable kinds, each = one
  # connector call. Coarse user-lifecycle events (user.terminated/suspended) are
  # never published — they decompose into per-access access.revoked.
  #
  # Built purely from the AuditEvent + live User/Role/Application — never the
  # Access row, which is already destroyed by the time a revoke is projected
  # (emit-before-destroy). Only the access id (a correlation handle) is read from
  # the audit targets.
  #
  # User identity contract (decided 2026-06-17): `data.user` carries `id` (our
  # immutable UUID), `email` (the conventional cross-system match key), and
  # `name`. Bridge authors: KEY YOUR PERSISTENT USER→TARGET-ACCOUNT MAPPING ON
  # `id` — it never changes; `email` is mutable (a rename makes a later revoke
  # carry the new email) so use it only for the FIRST resolution. We deliberately
  # do NOT send `external_identities` (HRIS namespace — wrong identity space for
  # target provisioning) nor any target-account id (that would be target *state*
  # in the decision plane — the same boundary violation as an entitlement `ref`
  # on Role). Resolving our user to a target account is the bridge's job, exactly
  # like role→entitlement. Adding identifiers later is additive (non-breaking per
  # the dataschema versioning policy), so this stays minimal until a real bridge
  # for a non-email-keyed system (AWS/GitHub/AD) needs more.
  class CloudEventBuilder
    SPEC_VERSION = "1.0".freeze
    DATASCHEMA_VERSION = 1

    # internal audit event_type → published CloudEvent type
    TYPE_MAP = {
      "access.approved" => "com.governauthzer.access.approved",
      "access.revoked"  => "com.governauthzer.access.revoked"
    }.freeze

    # CloudEvents `source` identifies the producing instance. Configurable per
    # deployment; the dataschema host, by contrast, is the canonical project
    # registry (identical for every install of a given version).
    def self.event_source
      ENV.fetch("GOVERNAUTHZER_EVENT_SOURCE", "https://governauthzer.dev")
    end

    # Host the emitted `dataschema` URLs point at — the schema registry where the
    # versioned JSON Schemas are served. Configurable per deployment; the default
    # is the canonical project registry (the docs site, under /schemas), so a
    # consumer can dereference a known stable URL. Self-hosters who mirror the
    # schemas point this at their own host. Not hardcoded — overridable via ENV,
    # same pattern as `event_source`.
    def self.schema_host
      ENV.fetch("GOVERNAUTHZER_SCHEMA_HOST", "https://governauthzer.dev/schemas")
    end

    def self.publishable_type?(audit_event_type)
      TYPE_MAP.key?(audit_event_type)
    end

    # The CloudEvent types a subscription can filter on (the published contract).
    def self.published_types
      TYPE_MAP.values
    end

    def initialize(audit_event)
      @audit_event = audit_event
    end

    # The CloudEvent hash, or nil when the event must not be published outbound:
    # an unmapped type, a missing user/role (data-integrity edge), or the
    # self/operator application (never provisioned externally).
    def build
      ce_type = TYPE_MAP[@audit_event.event_type]
      return nil if ce_type.nil?

      role = Role.find_by(id: @audit_event.target_id("Role"))
      user = User.find_by(id: @audit_event.target_id("User"))
      return nil if role.nil? || user.nil?
      return nil if role.application.self_app?

      {
        "specversion" => SPEC_VERSION,
        "id" => @audit_event.id,
        "source" => self.class.event_source,
        "type" => ce_type,
        "time" => @audit_event.occurred_at.utc.iso8601,
        "subject" => "access/#{@audit_event.target_id('Access')}",
        "datacontenttype" => "application/json",
        "dataschema" => dataschema,
        "data" => data(user, role, role.application)
      }
    end

    private

    def dataschema
      "#{self.class.schema_host}/#{@audit_event.event_type}/#{DATASCHEMA_VERSION}.json"
    end

    def data(user, role, application)
      payload = {
        "access_id" => @audit_event.target_id("Access"),
        "user" => { "id" => user.id, "email" => user.email, "name" => user.name },
        "role" => { "id" => role.id, "slug" => role.slug, "name" => role.name },
        "application" => { "id" => application.id, "slug" => application.slug, "name" => application.name }
      }
      reason = @audit_event.metadata&.dig("reason")
      payload["reason"] = reason if reason
      payload
    end
  end
end

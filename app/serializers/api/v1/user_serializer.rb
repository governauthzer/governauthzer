class Api::V1::UserSerializer < Api::V1::BaseSerializer
  def as_json
    {
      "id" => object.id,
      "email" => object.email,
      "name" => object.name,
      "status" => object.status,
      "manager_id" => object.manager_id,
      "department" => object.department,
      "title" => object.title,
      "start_date" => object.start_date&.iso8601,
      "end_date" => object.end_date&.iso8601,
      "created_at" => object.created_at.iso8601,
      "updated_at" => object.updated_at.iso8601,
      "external_identities" => external_identities,
      "omniauth_identities" => omniauth_identities,
      "roles" => roles
    }
  end

  private

  def external_identities
    object.external_identities.map do |ei|
      { "id" => ei.id, "source" => ei.source, "external_id" => ei.external_id }
    end
  end

  def omniauth_identities
    object.omniauth_identities.map do |oi|
      { "id" => oi.id, "auth_provider_slug" => oi.auth_provider.slug, "subject" => oi.subject }
    end
  end

  def roles
    object.accesses.select(&:approved?).map do |access|
      {
        "id" => access.role.id,
        "slug" => access.role.slug,
        "name" => access.role.name,
        "application_slug" => access.role.application.slug
      }
    end
  end
end

class Api::V1::GrantSerializer < Api::V1::BaseSerializer
  # The bulk twin of the outbound access event's `data`: same coordinates
  # (application.slug + role.slug + user), minimal fields. The bridge resolves
  # (application.slug, role.slug) -> a target group and keys the user mapping on
  # the immutable user.id.
  def as_json
    {
      "application" => { "slug" => object.role.application.slug },
      "role" => { "slug" => object.role.slug },
      "user" => { "id" => object.user.id, "email" => object.user.email }
    }
  end
end

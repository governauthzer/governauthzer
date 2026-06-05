class DocsController < ApplicationController
  # Public API documentation — the OpenAPI contract is public by design, no auth.

  # GET /api-docs — thin HTML page mounting Redoc, pointed at the YAML below.
  def show
    render layout: false
  end

  # GET /api-docs/v1.yaml — serves the hand-authored OpenAPI contract verbatim.
  def spec
    send_file Rails.root.join("openapi/v1.yaml"),
              type: "application/yaml",
              disposition: "inline"
  end
end

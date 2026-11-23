class DocsController < ApplicationController
  # Public API documentation — the OpenAPI contract is public by design, no auth.

  # The page runs a large third-party bundle (Redoc) on the app's origin, so it gets a
  # strict policy of its own: nothing loads from anywhere else. That also stops Redoc's
  # "powered by" logo request to its CDN. Redoc injects its styles and runs its search
  # index in a blob: worker, hence those two allowances.
  content_security_policy do |policy|
    policy.default_src :self
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.img_src     :self, :data
    policy.font_src    :self, :data
    policy.worker_src  :blob
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :none
    policy.frame_ancestors :none
  end

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

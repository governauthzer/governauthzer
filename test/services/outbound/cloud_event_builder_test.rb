require "test_helper"

class Outbound::CloudEventBuilderTest < ActiveSupport::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    @app = Application.create!(name: "Slack", slug: "slack")
    @role = Role.create!(application: @app, name: "Slack User", slug: "slack-user")
    @user = User.create!(email: "ada@example.com", name: "Ada")
    @access = Access.create!(user: @user, role: @role, status: "approved")
  end

  def approved_event
    AuditEvent.record!(
      event_type: "access.approved", actor: :system,
      targets: [ @user, @access, @role ],
      metadata: { "source" => "admin-ui", "via" => "approval" }
    )
  end

  test "source identifies this deployment, not the project" do
    assert_equal Rails.application.config.x.base_url,
                 Outbound::CloudEventBuilder.new(approved_event).build["source"],
                 "a project-wide source would be identical on every install"
  end

  test "source can be published under a different identifier than the app is reached at" do
    with_env("GOVERNAUTHZER_EVENT_SOURCE" => "https://iga.example.com") do
      assert_equal "https://iga.example.com", Outbound::CloudEventBuilder.new(approved_event).build["source"]
    end
  end

  test "builds a CloudEvent for access.approved" do
    ce = Outbound::CloudEventBuilder.new(approved_event).build

    assert_equal "1.0", ce["specversion"]
    assert_equal "com.governauthzer.access.approved", ce["type"]
    assert_equal "https://governauthzer.dev/schemas/access.approved/1.json", ce["dataschema"]
    assert_equal "application/json", ce["datacontenttype"]
    assert_equal "access/#{@access.id}", ce["subject"]
    assert_equal "ada@example.com", ce.dig("data", "user", "email")
    assert_equal "slack-user", ce.dig("data", "role", "slug")
    assert_equal "slack", ce.dig("data", "application", "slug")
    assert_equal @access.id, ce.dig("data", "access_id")
  end

  test "CloudEvent id equals the AuditEvent id (idempotency + reconciliation correlation)" do
    ev = approved_event
    assert_equal ev.id, Outbound::CloudEventBuilder.new(ev).build["id"]
  end

  test "access.revoked carries the reason and survives the access row being destroyed" do
    ev = AuditEvent.record!(
      event_type: "access.revoked", actor: :system,
      targets: [ @user, @access, @role ],
      metadata: { "source" => "system", "via" => "expiry_sweeper", "reason" => "grant_expired" }
    )
    @access.destroy! # emit-before-destroy: the row is already gone when projection runs

    ce = Outbound::CloudEventBuilder.new(ev).build

    assert_equal "com.governauthzer.access.revoked", ce["type"]
    assert_equal "grant_expired", ce.dig("data", "reason")
    assert_equal "ada@example.com", ce.dig("data", "user", "email") # rebuilt from the live User
  end

  test "non-published audit events return nil" do
    ev = AuditEvent.record!(event_type: "auth.login.succeeded", actor: @user, targets: [ @user ])
    assert_nil Outbound::CloudEventBuilder.new(ev).build
  end

  test "the self/operator application is never published outbound" do
    self_app = Application.create!(name: "governauthzer", slug: "governauthzer")
    op_role = Role.create!(application: self_app, name: "Operator", slug: "operator", protected: true)
    op_access = Access.create!(user: @user, role: op_role, status: "approved")
    ev = AuditEvent.record!(
      event_type: "access.approved", actor: :system,
      targets: [ @user, op_access, op_role ], metadata: {}
    )

    assert_nil Outbound::CloudEventBuilder.new(ev).build
  end

  test "publishable_type? gates on the allowlist" do
    assert Outbound::CloudEventBuilder.publishable_type?("access.approved")
    assert Outbound::CloudEventBuilder.publishable_type?("access.revoked")
    assert_not Outbound::CloudEventBuilder.publishable_type?("user.terminated")
    assert_not Outbound::CloudEventBuilder.publishable_type?("auth.login.succeeded")
  end

  private

  def with_env(values)
    previous = values.transform_values { |_| nil }.merge(ENV.slice(*values.keys))
    ENV.update(values)
    yield
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end

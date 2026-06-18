require "test_helper"

class AccessTest < ActiveSupport::TestCase
  def setup
    Current.correlation_id = SecureRandom.uuid
    app = Application.create!(name: "Slack", slug: "slack")
    role = Role.create!(application: app, name: "Member", slug: "member")
    @user = User.create!(email: "a@example.com", name: "A")
    @access = Access.create!(user: @user, role: role, status: "approved")
  end

  test "provisioning_status defaults to not_required" do
    assert_equal "not_required", @access.provisioning_status
  end

  test "provisioning_status validates inclusion" do
    @access.provisioning_status = "bogus"
    assert_not @access.valid?
    assert_includes @access.errors.attribute_names, :provisioning_status
  end

  test "the four provisioning states are valid" do
    Access::PROVISIONING_STATUSES.each do |state|
      @access.provisioning_status = state
      assert @access.valid?, "#{state} should be valid"
    end
  end
end

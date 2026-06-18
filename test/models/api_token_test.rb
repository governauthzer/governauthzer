require "test_helper"

class ApiTokenTest < ActiveSupport::TestCase
  def make(**attrs)
    ApiToken.create!({ name: "t", token_digest: ApiToken.digest(ApiToken.generate_raw_token) }.merge(attrs))
  end

  test "scope defaults to full" do
    token = make
    assert_equal "full", token.scope
    assert token.full_access?
    assert_not token.reconcile_scoped?
  end

  test "reconcile scope flips the helpers" do
    token = make(scope: "reconcile")
    assert token.reconcile_scoped?
    assert_not token.full_access?
  end

  test "rejects an unknown scope" do
    token = ApiToken.new(name: "x", scope: "bogus", token_digest: "d")
    assert_not token.valid?
    assert_includes token.errors.attribute_names, :scope
  end
end

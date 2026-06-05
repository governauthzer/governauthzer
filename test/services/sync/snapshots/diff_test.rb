require "test_helper"

class Sync::Snapshots::DiffTest < ActiveSupport::TestCase
  # Fixtures: workday has alice (EMP-1001) and bob (EMP-1002).

  test "buckets incoming into new / existing / gone" do
    payload = [
      { external_id: "EMP-1001", email: "alice@example.com", name: "Alice" },
      { external_id: "EMP-1003", email: "carol@example.com", name: "Carol" }
    ]

    result = Sync::Snapshots::Diff.new(source: "workday", users: payload).compute

    assert_equal [ "EMP-1003" ], result.new_users.map { |u| u[:external_id] }
    assert_equal [ "EMP-1001" ], result.existing.map { |e| e[:payload][:external_id] }
    assert_equal [ "EMP-1002" ], result.gone.map { |g| g[:external_id] }
  end

  test "flags a gone single-source user as orphan" do
    bob = users(:bob)
    payload = [ { external_id: "EMP-1001", email: "alice@example.com", name: "Alice" } ]

    result = Sync::Snapshots::Diff.new(source: "workday", users: payload).compute

    assert_includes result.orphan_user_ids, bob.id
  end

  test "does not flag a gone user who has another source" do
    bob = users(:bob)
    ExternalIdentity.create!(user: bob, source: "bamboo", external_id: "B-2")
    payload = [ { external_id: "EMP-1001", email: "alice@example.com", name: "Alice" } ]

    result = Sync::Snapshots::Diff.new(source: "workday", users: payload).compute

    assert_not_includes result.orphan_user_ids, bob.id
  end

  test "writes nothing" do
    payload = [ { external_id: "EMP-1003", email: "carol@example.com", name: "Carol" } ]

    assert_no_difference([ "User.count", "ExternalIdentity.count" ]) do
      Sync::Snapshots::Diff.new(source: "workday", users: payload).compute
    end
  end
end

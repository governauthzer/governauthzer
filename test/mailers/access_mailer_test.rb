require "test_helper"

class AccessMailerTest < ActionMailer::TestCase
  test "review_request renders to the approver with request details" do
    mail = AccessMailer.with(
      email: "mgr@example.com", name: "Marvin", requester_name: "Ada",
      role_name: "Slack Member", application_name: "Slack", justification: "need it"
    ).review_request

    assert_equal [ "mgr@example.com" ], mail.to
    assert_match "awaiting your approval", mail.subject
    body = mail.body.encoded
    assert_match "Ada", body
    assert_match "Slack Member", body
    assert_match "need it", body
  end

  test "request_approved renders to the subject" do
    mail = AccessMailer.with(
      email: "ada@example.com", name: "Ada", role_name: "Slack Member", application_name: "Slack"
    ).request_approved

    assert_equal [ "ada@example.com" ], mail.to
    assert_match "approved", mail.subject
    assert_match "Slack Member", mail.body.encoded
  end

  test "request_denied renders with the comment" do
    mail = AccessMailer.with(
      email: "ada@example.com", name: "Ada", role_name: "Slack Member",
      application_name: "Slack", comment: "not now"
    ).request_denied

    assert_equal [ "ada@example.com" ], mail.to
    assert_match "denied", mail.subject
    assert_match "not now", mail.body.encoded
  end
end

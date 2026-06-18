require "test_helper"

class Outbound::SignerTest < ActiveSupport::TestCase
  test "produces a stable sha256= HMAC over timestamp.body" do
    sig = Outbound::Signer.signature(secret: "shh", timestamp: 1_700_000_000, body: '{"a":1}')
    expected = "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", "shh", '1700000000.{"a":1}')
    assert_equal expected, sig
  end

  test "different body or timestamp changes the signature" do
    base = Outbound::Signer.signature(secret: "shh", timestamp: 1, body: "x")
    assert_not_equal base, Outbound::Signer.signature(secret: "shh", timestamp: 2, body: "x")
    assert_not_equal base, Outbound::Signer.signature(secret: "shh", timestamp: 1, body: "y")
    assert_not_equal base, Outbound::Signer.signature(secret: "other", timestamp: 1, body: "x")
  end
end

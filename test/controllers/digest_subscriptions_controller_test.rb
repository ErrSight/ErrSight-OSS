require "test_helper"

class DigestSubscriptionsControllerTest < ActionDispatch::IntegrationTest
  # Public, token-based endpoint — no authentication required. The token is
  # signed (MessageVerifier) and embeds the membership id, so the only
  # interesting cross-tenant question is: can a token signed for membership A
  # disable digest for membership B? (It must not.)

  setup do
    @target = memberships(:team_member)
    @other  = memberships(:team_viewer)
    @target.update!(weekly_digest_enabled: true)
    @other.update!(weekly_digest_enabled: true)
  end

  test "valid token disables only the membership it was signed for" do
    post digest_unsubscribe_path, params: { token: @target.digest_unsubscribe_token }
    assert_response :success

    assert_not @target.reload.weekly_digest_enabled
    assert @other.reload.weekly_digest_enabled
  end

  test "GET works (mail clients prefetch links) and disables the target" do
    get digest_unsubscribe_path, params: { token: @target.digest_unsubscribe_token }
    assert_response :success
    assert_not @target.reload.weekly_digest_enabled
  end

  test "invalid token renders gracefully and does not change any membership" do
    post digest_unsubscribe_path, params: { token: "forged-token-abc" }
    assert_response :success
    assert @target.reload.weekly_digest_enabled
    assert @other.reload.weekly_digest_enabled
  end

  test "blank token does not change any membership" do
    post digest_unsubscribe_path, params: { token: "" }
    assert_response :success
    assert @target.reload.weekly_digest_enabled
  end

  test "tokens are not interchangeable between memberships" do
    # Even though both tokens look similar, the signed payload encodes the id.
    # Forging requires breaking the signature.
    target_token = @target.digest_unsubscribe_token
    other_token  = @other.digest_unsubscribe_token
    assert_not_equal target_token, other_token

    post digest_unsubscribe_path, params: { token: target_token }
    assert_not @target.reload.weekly_digest_enabled
    assert @other.reload.weekly_digest_enabled
  end
end

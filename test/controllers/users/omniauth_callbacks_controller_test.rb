require "test_helper"

class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true

    # ErrSight OSS defaults to invite-only (ALLOW_PUBLIC_SIGNUP=false). Most
    # existing tests in this file assume open signup is allowed, so flip the
    # gate on here. New gate tests explicitly override to "false".
    @original_signup_env = ENV["ALLOW_PUBLIC_SIGNUP"]
    ENV["ALLOW_PUBLIC_SIGNUP"] = "true"
  end

  teardown do
    ENV["ALLOW_PUBLIC_SIGNUP"] = @original_signup_env
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  # ── Google ──────────────────────────────────────────────────────────────────

  test "google callback creates a new user and signs them in" do
    mock_google("google-uid-new", email: "newgoogler@example.com", name: "New Googler")

    assert_difference "User.count", 1 do
      post user_google_oauth2_omniauth_callback_path
    end

    user = User.find_by(email: "newgoogler@example.com")
    assert_equal "google_oauth2", user.provider
    assert_equal "google-uid-new", user.uid
    assert user.confirmed?, "OAuth users skip email confirmation"
    assert_response :redirect
  end

  test "google callback auto-creates a personal organization for the new user" do
    mock_google("google-uid-org", email: "newowner@example.com", name: "New Owner")

    assert_difference "Organization.count", 1 do
      post user_google_oauth2_omniauth_callback_path
    end

    user = User.find_by(email: "newowner@example.com")
    assert_equal 1, user.organizations.count
    assert_equal user, user.organizations.first.owner
  end

  test "google callback skips org creation when a pending invitation matches the email" do
    org = organizations(:team_org)
    Invitation.create!(
      organization: org,
      invited_by: users(:team_owner),
      email: "invitee@example.com",
      role: :member,
      token: SecureRandom.hex(20),
      expires_at: 7.days.from_now
    )

    mock_google("google-uid-invitee", email: "invitee@example.com", name: "Invitee")

    assert_difference "User.count", 1 do
      assert_no_difference "Organization.count" do
        post user_google_oauth2_omniauth_callback_path
      end
    end
  end

  test "google callback signs in an existing user without creating a duplicate" do
    User.create!(
      email: "existing@example.com", name: "Existing", password: "password123",
      provider: "google_oauth2", uid: "google-uid-existing", confirmed_at: Time.current
    )
    mock_google("google-uid-existing", email: "existing@example.com", name: "Existing")

    assert_no_difference "User.count" do
      post user_google_oauth2_omniauth_callback_path
    end
    assert_response :redirect
  end

  test "google callback for a discarded user blocks sign-in with an alert" do
    user = User.create!(
      email: "deleted@example.com", name: "Deleted", password: "password123",
      provider: "google_oauth2", uid: "google-uid-deleted", confirmed_at: Time.current
    )
    user.discard!
    mock_google("google-uid-deleted", email: "deleted@example.com", name: "Deleted")

    post user_google_oauth2_omniauth_callback_path

    assert_redirected_to new_user_session_url
    assert_match(/deleted/i, flash[:alert])
  end

  # ── GitHub ──────────────────────────────────────────────────────────────────

  test "github callback creates a new user and signs them in" do
    mock_github("github-uid-new", email: "newgh@example.com", name: "New GH")

    assert_difference "User.count", 1 do
      post user_github_omniauth_callback_path
    end

    user = User.find_by(email: "newgh@example.com")
    assert_equal "github", user.provider
    assert_equal "github-uid-new", user.uid
    assert user.confirmed?
    assert_response :redirect
  end

  # GitHub doesn't always return an email (private email setting). The model
  # falls back to a synthesized "<provider>-<uid>@oauth.errsight.local" address.
  test "github callback synthesizes a placeholder email when GitHub omits it" do
    mock_github("github-uid-noemail", email: nil, name: "Private User")

    assert_difference "User.count", 1 do
      post user_github_omniauth_callback_path
    end

    user = User.find_by(uid: "github-uid-noemail")
    assert_equal "github-github-uid-noemail@oauth.errsight.local", user.email
  end

  # ── Invite-only access model (ALLOW_PUBLIC_SIGNUP) ────────────────────────

  test "google callback blocks new-user signup when public signup disabled and no pending invitation" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"
    mock_google("google-uid-gated", email: "gated@example.com", name: "Gated")

    assert_no_difference "User.count" do
      post user_google_oauth2_omniauth_callback_path
    end

    assert_redirected_to new_user_session_url
    assert_match(/invitation only/i, flash[:alert])
  end

  test "google callback allows new-user signup when public signup disabled but email has a pending invitation" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"
    org = organizations(:team_org)
    Invitation.create!(
      organization: org,
      invited_by: users(:team_owner),
      email: "invited-via-oauth@example.com",
      role: :member,
      token: SecureRandom.hex(20),
      expires_at: 7.days.from_now
    )

    mock_google("google-uid-invited-oauth", email: "invited-via-oauth@example.com", name: "Invited")

    assert_difference "User.count", 1 do
      post user_google_oauth2_omniauth_callback_path
    end
  end

  test "google callback signs in an existing user even when public signup is disabled" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"
    User.create!(
      email: "existing-during-gate@example.com",
      name: "Existing",
      password: "password123",
      provider: "google_oauth2",
      uid: "google-uid-existing-gate",
      confirmed_at: Time.current
    )

    mock_google("google-uid-existing-gate", email: "existing-during-gate@example.com", name: "Existing")

    assert_no_difference "User.count" do
      post user_google_oauth2_omniauth_callback_path
    end

    assert_response :redirect
    assert_no_match(/invitation only/i, flash[:alert].to_s)
  end

  test "github callback blocks new-user signup when public signup disabled and no pending invitation" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"
    mock_github("github-uid-gated", email: "gh-gated@example.com", name: "GH Gated")

    assert_no_difference "User.count" do
      post user_github_omniauth_callback_path
    end

    assert_redirected_to new_user_session_url
    assert_match(/invitation only/i, flash[:alert])
  end

  private

  def mock_google(uid, email:, name:)
    auth = OmniAuth::AuthHash.new(provider: "google_oauth2", uid: uid, info: { email: email, name: name })
    OmniAuth.config.mock_auth[:google_oauth2] = auth
    Rails.application.env_config["omniauth.auth"] = auth
  end

  def mock_github(uid, email:, name:)
    auth = OmniAuth::AuthHash.new(provider: "github", uid: uid, info: { email: email, name: name })
    OmniAuth.config.mock_auth[:github] = auth
    Rails.application.env_config["omniauth.auth"] = auth
  end
end

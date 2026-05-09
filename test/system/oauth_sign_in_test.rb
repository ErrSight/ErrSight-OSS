require "application_system_test_case"

class OauthSignInTest < ApplicationSystemTestCase
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.logger = Rails.logger
  end

  teardown do
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.test_mode = false
  end

  test "new user signs up via Google and lands on the dashboard" do
    mock_google("google-sys-new", email: "newgoogle@example.com", name: "Sys Google")

    visit new_user_registration_path
    click_button "Continue with Google"

    assert_current_path authenticated_root_path
    assert User.exists?(email: "newgoogle@example.com"), "expected new user to be created"
  end

  test "existing OAuth user signs in via Google and lands on the dashboard" do
    user = User.create!(
      email: "returning@example.com",
      name: "Returning User",
      password: "password123",
      provider: "google_oauth2",
      uid: "google-sys-returning",
      confirmed_at: Time.current
    )
    org = Organization.create!(name: "Returning Org", owner: user)
    org.memberships.create!(user: user, role: :admin)

    mock_google("google-sys-returning", email: "returning@example.com", name: "Returning User")

    visit new_user_session_path
    click_button "Continue with Google"

    assert_current_path authenticated_root_path
  end

  test "new user signs up via GitHub and lands on the dashboard" do
    mock_github("github-sys-new", email: "newgh@example.com", name: "Sys GH")

    visit new_user_registration_path
    click_button "Continue with GitHub"

    assert_current_path authenticated_root_path
    assert User.exists?(email: "newgh@example.com")
  end

  test "GitHub callback handles users without a public email" do
    mock_github("github-sys-noemail", email: nil, name: "Anon")

    visit new_user_registration_path
    click_button "Continue with GitHub"

    assert_current_path authenticated_root_path
    user = User.find_by(uid: "github-sys-noemail")
    assert_not_nil user
    assert_equal "github-github-sys-noemail@oauth.errsight.local", user.email
  end

  private

  def mock_google(uid, email:, name:)
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: { email: email, name: name }
    )
  end

  def mock_github(uid, email:, name:)
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: uid,
      info: { email: email, name: name }
    )
  end
end

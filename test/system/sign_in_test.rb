require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "user signs in with valid credentials and lands on the dashboard" do
    visit new_user_session_path

    fill_in "Email",    with: "user@example.com"
    fill_in "Password", with: "password123"
    click_button "Sign in"

    assert_current_path authenticated_root_path
    assert_text "Dashboard"
    assert_text "Regular Org"
  end

  test "invalid credentials keep the user on the sign-in page with an error" do
    visit new_user_session_path

    fill_in "Email",    with: "user@example.com"
    fill_in "Password", with: "wrong-password"
    click_button "Sign in"

    assert_text "Invalid email or password."
    assert_selector "form[action='#{user_session_path}']"
  end

  # Devise paranoid mode: a sign-in attempt against a non-existent email must
  # produce the same response as a wrong-password attempt against a real email.
  # Without this guarantee an attacker can enumerate registered emails by
  # observing flash text differences.
  test "non-existent email gives the same generic error as wrong password" do
    visit new_user_session_path
    fill_in "Email",    with: "ghost-account-#{SecureRandom.hex(4)}@example.com"
    fill_in "Password", with: "password123"
    click_button "Sign in"

    assert_text "Invalid email or password."
    assert_no_text(/no account|not found|doesn'?t exist|never registered/i)
    assert_selector "form[action='#{user_session_path}']"
  end

  test "unauthenticated visit to /dashboard redirects to sign-in" do
    visit dashboard_path
    assert_current_path new_user_session_path
    assert_text "Sign in"
  end
end

require "test_helper"

class ImpersonationsControllerTest < ActionDispatch::IntegrationTest
  # ImpersonationsController#destroy "stops impersonating" — it reads
  # session[:true_admin_id], verifies the recovered user is still an admin,
  # and signs them back in. Anything else (missing key / non-admin /
  # deleted admin) must sign the request out and redirect to sign-in,
  # never escalate privileges.

  test "DELETE /impersonate without a true_admin_id in session signs out and redirects to sign-in" do
    sign_in users(:regular)
    delete stop_impersonating_path
    assert_redirected_to new_user_session_path
    assert_equal "Not impersonating.", flash[:alert]
  end

  test "round-trip: admin becomes a user, then stops impersonating, returns to admin panel" do
    admin = users(:admin)
    target = users(:regular)
    sign_in admin
    post become_admin_user_path(target)
    # After become, the session has true_admin_id set and current_user is target.
    delete stop_impersonating_path
    assert_redirected_to admin_root_path
    assert_equal "Returned to admin account.", flash[:notice]
  end

  test "non-admin cannot initiate impersonation via /admin/users/:id/become" do
    sign_in users(:regular)
    post become_admin_user_path(users(:member_user))
    # ActiveAdmin's authenticate_admin! must redirect a non-admin out of /admin
    # WITHOUT writing true_admin_id (the impersonation marker). If session
    # carried that key, the next request to DELETE /impersonate would silently
    # escalate this user back into the admin panel.
    assert_response :redirect
    assert_nil session[:true_admin_id], "non-admin must never get true_admin_id in session"

    # Concrete confirmation: a follow-up DELETE /impersonate must not return
    # the user to admin_root — it must sign them out instead.
    delete stop_impersonating_path
    assert_redirected_to new_user_session_path
  end

  test "admin cannot impersonate another admin" do
    sign_in users(:admin)
    other_admin = User.create!(
      email: "second_admin@example.com",
      password: "password123",
      name: "Second Admin",
      admin: true,
      confirmed_at: Time.current
    )
    post become_admin_user_path(other_admin)
    assert_redirected_to admin_user_path(other_admin.id)
    assert_equal "Impersonating another admin is not allowed.", flash[:alert]
  end

  test "admin cannot impersonate a discarded user" do
    skip "Discard column not present" unless User.column_names.include?("discarded_at")
    sign_in users(:admin)
    target = users(:regular)
    target.update_columns(discarded_at: Time.current)
    post become_admin_user_path(target)
    assert_redirected_to admin_user_path(target.id)
    assert_equal "Cannot impersonate a deleted user.", flash[:alert]
  ensure
    target&.update_columns(discarded_at: nil)
  end
end

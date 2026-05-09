require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:regular)
    @org  = organizations(:regular_org)
    @org.memberships.find_or_create_by!(user: @user) { |m| m.role = :admin }
  end

  # ── Account deletion (DELETE /users) ──────────────────────────────────────

  test "DELETE /users is blocked when user owns an org with other members" do
    teammate = users(:member_user)
    @org.memberships.find_or_create_by!(user: teammate) { |m| m.role = :member }
    @org.update!(owner: @user)

    sign_in @user
    delete user_registration_path

    assert_redirected_to edit_user_registration_path
    assert_match "Remove all other members", flash[:alert]
    assert_not @user.reload.discarded?
  end

  test "DELETE /users discards the user and cascades to solo-owned orgs" do
    solo_org = Organization.create!(name: "Solo", slug: "solo-#{@user.id}", owner: @user)
    solo_org.memberships.create!(user: @user, role: :admin)

    sign_in @user
    delete user_registration_path

    assert @user.reload.discarded?
    assert solo_org.reload.discarded?
  end

  test "DELETE /users pauses ingestion on the solo-owned org's projects" do
    solo_org = Organization.create!(name: "Solo3", slug: "solo3-#{@user.id}", owner: @user)
    solo_org.memberships.create!(user: @user, role: :admin)
    project = solo_org.projects.create!(
      name: "Pet Project", user: @user, api_key: "elp_#{SecureRandom.hex(24)}"
    )

    sign_in @user
    delete user_registration_path

    assert project.reload.ingestion_paused?
  end

  # ── Sign-up (POST /users) ─────────────────────────────────────────────────

  test "POST /users creates the user and an auto-org" do
    assert_difference -> { User.count }, 1 do
      assert_difference -> { Organization.count }, 1 do
        post user_registration_path, params: {
          user: {
            name: "New User",
            email: "newuser@example.com",
            password: "password123",
            password_confirmation: "password123",
            organization_name: "New Org"
          }
        }
      end
    end

    new_user = User.find_by(email: "newuser@example.com")
    assert_not_nil new_user
    org = new_user.organizations.first
    assert_equal "New Org", org.name
    assert_equal new_user, org.owner
  end

  test "POST /users does NOT create a personal org when a pending invite matches the email" do
    Invitation.create!(
      organization: @org,
      invited_by: @user,
      email: "invitee@example.com",
      role: :member,
      token: SecureRandom.hex(20),
      expires_at: 7.days.from_now
    )

    assert_difference -> { User.count }, 1 do
      assert_no_difference -> { Organization.count } do
        post user_registration_path, params: {
          user: {
            name: "Invitee",
            email: "invitee@example.com",
            password: "password123",
            password_confirmation: "password123"
          }
        }
      end
    end
  end
end

require "test_helper"

class Users::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include StubHelper

  setup do
    @user = users(:regular)
    @org  = organizations(:regular_org)
    @org.memberships.find_or_create_by!(user: @user) { |m| m.role = :admin }

    # ErrSight OSS defaults to invite-only (ALLOW_PUBLIC_SIGNUP=false). Most
    # tests in this file predate that change and assume public signup is
    # allowed, so flip it on here and restore in teardown. New gate tests
    # explicitly override to "false" within the test body.
    @original_signup_env = ENV["ALLOW_PUBLIC_SIGNUP"]
    ENV["ALLOW_PUBLIC_SIGNUP"] = "true"
  end

  teardown do
    ENV["ALLOW_PUBLIC_SIGNUP"] = @original_signup_env
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

  # ── Cloudflare Turnstile gate ──────────────────────────────────────────────

  test "POST /users blocks signup when Turnstile is enabled and verification fails" do
    stub_method(CloudflareTurnstile, :enabled?, true) do
      stub_method(CloudflareTurnstile, :verify, false) do
        assert_no_difference -> { User.count } do
          post user_registration_path, params: {
            user: {
              name: "Blocked Bot",
              email: "blocked-bot@example.com",
              password: "password123",
              password_confirmation: "password123"
            },
            "cf-turnstile-response" => "bad-token"
          }
        end

        assert_response :unprocessable_entity
        assert_match(/bot verification failed/i, response.body)
      end
    end
  end

  test "POST /users allows signup when Turnstile verification succeeds" do
    stub_method(CloudflareTurnstile, :enabled?, true) do
      stub_method(CloudflareTurnstile, :verify, true) do
        assert_difference -> { User.count }, 1 do
          post user_registration_path, params: {
            user: {
              name: "Verified Human",
              email: "verified-human@example.com",
              password: "password123",
              password_confirmation: "password123"
            },
            "cf-turnstile-response" => "good-token"
          }
        end
      end
    end
  end

  # ── Invite-only access model (ALLOW_PUBLIC_SIGNUP) ────────────────────────

  test "GET /users/sign_up redirects to sign-in when public signup is disabled" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"

    get new_user_registration_path

    assert_redirected_to new_user_session_path
    assert_match(/registration is disabled/i, flash[:alert])
  end

  test "POST /users is blocked when public signup is disabled and no invitation token" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"

    assert_no_difference -> { User.count } do
      post user_registration_path, params: {
        user: {
          name: "Blocked Signup",
          email: "blocked@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end

    assert_redirected_to new_user_session_path
    assert_match(/registration is disabled/i, flash[:alert])
  end

  test "POST /users succeeds when public signup is disabled but invitee landed via invitation link" do
    ENV["ALLOW_PUBLIC_SIGNUP"] = "false"

    invite = Invitation.create!(
      organization: @org,
      invited_by: @user,
      email: "gated-invitee@example.com",
      role: :member,
      token: SecureRandom.hex(20),
      expires_at: 7.days.from_now
    )

    # InvitationsController#show stores the token in the session — simulate
    # by hitting the invitation URL before posting to /users.
    get invitation_show_path(invite.token)

    assert_difference -> { User.count }, 1 do
      post user_registration_path, params: {
        user: {
          name: "Gated Invitee",
          email: "gated-invitee@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
  end
end

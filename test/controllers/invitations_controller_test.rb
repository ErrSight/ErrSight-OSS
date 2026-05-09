require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:team_owner)
    @member   = users(:member_user)
    @viewer   = users(:viewer_user)
    @outsider = users(:over_limit)
    @org      = organizations(:team_org)
    @org.memberships.find_or_create_by!(user: @admin)  { |m| m.role = :admin }
    @org.memberships.find_or_create_by!(user: @member) { |m| m.role = :member }
    @org.memberships.find_or_create_by!(user: @viewer) { |m| m.role = :viewer }
  end

  def invite_params(email: "newperson@example.com", role: "member")
    { invitation: { email: email, role: role } }
  end

  # ── create ────────────────────────────────────────────────────────────────────

  test "unauthenticated user cannot create" do
    post organization_invitations_path(@org), params: invite_params
    assert_redirected_to new_user_session_path
  end

  test "outsider cannot create an invitation for another org" do
    sign_in @outsider
    assert_no_difference -> { @org.invitations.count } do
      post organization_invitations_path(@org), params: invite_params
    end
    assert_redirected_to authenticated_root_path
  end

  test "viewer cannot invite" do
    sign_in @viewer
    assert_no_difference -> { @org.invitations.count } do
      post organization_invitations_path(@org), params: invite_params
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "member cannot invite" do
    sign_in @member
    assert_no_difference -> { @org.invitations.count } do
      post organization_invitations_path(@org), params: invite_params
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "admin can invite and mail is enqueued" do
    sign_in @admin
    assert_difference -> { @org.invitations.count }, 1 do
      assert_enqueued_emails 1 do
        post organization_invitations_path(@org), params: invite_params
      end
    end
    assert_redirected_to organization_memberships_path(@org)
  end

  test "rejects invalid role parameter" do
    sign_in @admin
    post organization_invitations_path(@org), params: invite_params(role: "superuser")
    assert_response :bad_request
  end

  # ── destroy ───────────────────────────────────────────────────────────────────

  test "accept refuses an invitation when the organization has been discarded" do
    invitation = @org.invitations.create!(email: "deadorg@example.com", role: :member, invited_by: @admin)
    user = User.create!(email: "deadorg@example.com", name: "Dead Org Invitee", password: "password123",
                        confirmed_at: Time.current)
    @org.discard!
    sign_in user

    assert_no_difference -> { Membership.count } do
      get accept_invitation_path(invitation.token)
    end
    assert_redirected_to root_path
    assert_match(/no longer active/i, flash[:alert])
    assert invitation.reload.pending?
    assert_nil session[:invitation_token]
  end

  test "viewer cannot revoke invitation" do
    sign_in @admin
    invitation = @org.invitations.create!(email: "pending@example.com", role: :member, invited_by: @admin)
    sign_out @admin
    sign_in @viewer

    assert_no_difference -> { @org.invitations.count } do
      delete organization_invitation_path(@org, invitation)
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "admin can revoke invitation" do
    sign_in @admin
    invitation = @org.invitations.create!(email: "pending@example.com", role: :member, invited_by: @admin)
    assert_difference -> { @org.invitations.count }, -1 do
      delete organization_invitation_path(@org, invitation)
    end
    assert_redirected_to organization_memberships_path(@org)
  end

  # ── public accept ─────────────────────────────────────────────────────────────

  test "accept creates membership for invited user" do
    invitation = @org.invitations.create!(email: "bob@example.com", role: :member, invited_by: @admin)
    new_user = User.create!(email: "bob@example.com", name: "Bob", password: "password123",
                            confirmed_at: Time.current)
    sign_in new_user

    assert_difference -> { @org.memberships.count }, 1 do
      get accept_invitation_path(invitation.token)
    end
    assert_redirected_to organization_path(@org)
    assert invitation.reload.accepted?
  end

  test "expired invitation cannot be accepted" do
    invitation = @org.invitations.create!(email: "old@example.com", role: :member, invited_by: @admin)
    invitation.update_columns(expires_at: 1.day.ago)
    new_user = User.create!(email: "old@example.com", name: "Oldie", password: "password123",
                            confirmed_at: Time.current)
    sign_in new_user

    assert_no_difference -> { @org.memberships.count } do
      get accept_invitation_path(invitation.token)
    end
    assert_redirected_to root_path
  end

  test "signed-in user with mismatched email cannot redeem someone else's invitation" do
    invitation = @org.invitations.create!(email: "intended@example.com", role: :member, invited_by: @admin)
    attacker = User.create!(email: "attacker@example.com", name: "Attacker", password: "password123",
                            confirmed_at: Time.current)
    sign_in attacker

    assert_no_difference -> { @org.memberships.count } do
      get accept_invitation_path(invitation.token)
    end
    assert_redirected_to root_path
    assert_match(/intended@example\.com/, flash[:alert])
    assert invitation.reload.pending?
    assert_nil session[:invitation_token]
  end

  test "accept matches email case-insensitively" do
    invitation = @org.invitations.create!(email: "mixed@example.com", role: :member, invited_by: @admin)
    user = User.create!(email: "Mixed@Example.com", name: "Mixed", password: "password123",
                        confirmed_at: Time.current)
    sign_in user

    assert_difference -> { @org.memberships.count }, 1 do
      get accept_invitation_path(invitation.token)
    end
    assert_redirected_to organization_path(@org)
    assert invitation.reload.accepted?
  end

  # ── auto-accept on sign-in ────────────────────────────────────────────────────

  test "signing in with a pending invite auto-accepts and lands on the dashboard" do
    invitation = @org.invitations.create!(email: "newhire@example.com", role: :member, invited_by: @admin)
    User.create!(email: "newhire@example.com", name: "New Hire", password: "password123",
                 confirmed_at: Time.current)

    assert_difference -> { @org.memberships.count }, 1 do
      post user_session_path, params: { user: { email: "newhire@example.com", password: "password123" } }
    end
    assert_redirected_to authenticated_root_path
    assert invitation.reload.accepted?
  end

  # ── stale session-token hygiene ──────────────────────────────────────────────

  test "accept clears session[:invitation_token] when the invitation is expired" do
    invitation = @org.invitations.create!(email: "deadlink@example.com", role: :member, invited_by: @admin)
    invitation.update_columns(expires_at: 1.day.ago)

    user = User.create!(email: "deadlink@example.com", name: "Dead Link", password: "password123",
                        confirmed_at: Time.current)
    sign_in user

    get accept_invitation_path(invitation.token)

    assert_redirected_to root_path
    assert_match(/no longer valid/i, flash[:alert])
    assert_nil session[:invitation_token]
  end

  test "accept clears session[:invitation_token] when the invitation has been declined" do
    invitation = @org.invitations.create!(email: "revoked@example.com", role: :member, invited_by: @admin)
    invitation.update!(status: :declined)

    user = User.create!(email: "revoked@example.com", name: "Rev", password: "password123",
                        confirmed_at: Time.current)
    sign_in user

    get accept_invitation_path(invitation.token)

    assert_redirected_to root_path
    assert_nil session[:invitation_token]
  end

  test "show recognizes existing user when invite email had mixed case" do
    User.create!(email: "exists@example.com", name: "Exists", password: "password123",
                 confirmed_at: Time.current)
    invitation = @org.invitations.create!(email: "Exists@Example.COM", role: :member, invited_by: @admin)

    get invitation_show_path(invitation.token)
    assert_response :success
    assert_select "form[action=?]", new_user_session_path
    assert_select "form[action=?]", user_registration_path, count: 0
  end

  test "show clears session[:invitation_token] when the invitation is expired" do
    invitation = @org.invitations.create!(email: "deadshow@example.com", role: :member, invited_by: @admin)
    invitation.update_columns(expires_at: 1.day.ago)

    get invitation_show_path(invitation.token)

    assert_response :success  # renders the :expired template
    assert_nil session[:invitation_token]
  end
end

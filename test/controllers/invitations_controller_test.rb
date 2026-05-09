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

  # ── resend ──────────────────────────────────────────────────────────────────

  test "admin can resend a pending invitation, re-enqueuing the mail and refreshing expiry" do
    sign_in @admin
    invitation = @org.invitations.create!(email: "resend@example.com", role: :member, invited_by: @admin)
    invitation.update_columns(expires_at: 1.day.from_now)  # near expiry, so the refresh is observable
    original_token = invitation.token

    assert_no_difference -> { @org.invitations.count } do
      assert_enqueued_emails 1 do
        post resend_organization_invitation_path(@org, invitation)
      end
    end

    assert_redirected_to organization_memberships_path(@org)
    assert_match(/re-sent to resend@example\.com/i, flash[:notice])
    invitation.reload
    # Same token/link — only the validity window moved forward.
    assert_equal original_token, invitation.token
    assert invitation.expires_at > 6.days.from_now
    assert invitation.pending?
  end

  test "cannot resend a time-expired invitation" do
    sign_in @admin
    invitation = @org.invitations.create!(email: "stale@example.com", role: :member, invited_by: @admin)
    # Expiry is timestamp-based; status stays :pending. Resend must still refuse it.
    invitation.update_columns(expires_at: 1.day.ago)

    assert_no_enqueued_emails do
      post resend_organization_invitation_path(@org, invitation)
    end
    assert_redirected_to organization_memberships_path(@org)
    assert_match(/expired/i, flash[:alert])
    # Window was not revived.
    assert invitation.reload.expires_at < Time.current
  end

  test "viewer cannot resend" do
    invitation = @org.invitations.create!(email: "noresend@example.com", role: :member, invited_by: @admin)
    sign_in @viewer

    assert_no_enqueued_emails do
      post resend_organization_invitation_path(@org, invitation)
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "member cannot resend" do
    invitation = @org.invitations.create!(email: "noresend2@example.com", role: :member, invited_by: @admin)
    sign_in @member

    assert_no_enqueued_emails do
      post resend_organization_invitation_path(@org, invitation)
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "outsider cannot resend an invitation for another org" do
    invitation = @org.invitations.create!(email: "noresend3@example.com", role: :member, invited_by: @admin)
    sign_in @outsider

    assert_no_enqueued_emails do
      post resend_organization_invitation_path(@org, invitation)
    end
    assert_redirected_to authenticated_root_path
  end

  test "cannot resend an invitation that is no longer pending" do
    sign_in @admin
    invitation = @org.invitations.create!(email: "accepted@example.com", role: :member, invited_by: @admin)
    invitation.update_columns(status: Invitation.statuses[:accepted])

    assert_no_enqueued_emails do
      post resend_organization_invitation_path(@org, invitation)
    end
    assert_redirected_to organization_memberships_path(@org)
    assert_match(/can't be re-sent/i, flash[:alert])
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

  # ── decline ───────────────────────────────────────────────────────────────────

  test "decline by anyone other than the invited user leaves the invitation pending" do
    invitation = @org.invitations.create!(email: "intended@example.com", role: :member, invited_by: @admin)

    # Logged out (just holding the token URL): bounced to sign in, untouched.
    post decline_invitation_path(invitation.token)
    assert_redirected_to new_user_session_path
    assert invitation.reload.pending?

    # Signed in as a different email: cannot void someone else's invitation.
    attacker = User.create!(email: "attacker@example.com", name: "Attacker", password: "password123",
                            confirmed_at: Time.current)
    sign_in attacker
    post decline_invitation_path(invitation.token)
    assert_redirected_to root_path
    assert invitation.reload.pending?
  end

  test "decline succeeds for the invited user" do
    invitation = @org.invitations.create!(email: "wanted@example.com", role: :member, invited_by: @admin)
    user = User.create!(email: "wanted@example.com", name: "Wanted", password: "password123",
                        confirmed_at: Time.current)
    sign_in user

    post decline_invitation_path(invitation.token)
    assert_redirected_to root_path
    assert invitation.reload.declined?
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

  # Regression: an invitee who is ALREADY signed in when the invite arrives (a
  # second tab, a remembered session, or signing in before being invited) never
  # re-runs after_sign_in_path_for, so its auto-accept never fired. The
  # ensure_organization_exists! gate must catch them on their next request and
  # pull them into the org rather than bouncing them to the org-create form.
  test "an already-signed-in no-org user is auto-accepted into a pending invite instead of being bounced to org-create" do
    user = User.create!(email: "latebind@example.com", name: "Late Bind", password: "password123",
                        confirmed_at: Time.current)
    sign_in user
    # Invite arrives AFTER sign-in — this session never hit the sign-in auto-accept.
    invitation = @org.invitations.create!(email: "latebind@example.com", role: :member, invited_by: @admin)

    get dashboard_path

    assert_response :success, "expected the gate to auto-accept and let the user through, not redirect to org-create"
    assert @org.membership_for(user), "expected the pending invite to be auto-accepted into a membership"
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

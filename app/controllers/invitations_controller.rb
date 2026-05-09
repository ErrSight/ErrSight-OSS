class InvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show, :accept, :decline ]
  before_action :set_organization, only: [ :create, :destroy, :resend ]
  before_action :set_invitation_by_token, only: [ :show, :accept, :decline ]

  def create
    @invitation = @organization.invitations.build(invitation_params.merge(invited_by: current_user))
    authorize @invitation

    if @invitation.save
      InvitationMailer.invite(@invitation).deliver_later
      redirect_to organization_memberships_path(@organization), notice: "Invitation sent to #{@invitation.email}."
    else
      redirect_to organization_memberships_path(@organization), alert: @invitation.errors.full_messages.join(", ")
    end
  end

  def destroy
    @invitation = @organization.invitations.find(params[:id])
    authorize @invitation
    @invitation.destroy
    respond_to do |format|
      format.html { redirect_to organization_memberships_path(@organization), notice: "Invitation revoked." }
      format.turbo_stream
    end
  end

  # Re-deliver an invitation email — for when the original never reached the
  # invitee (spam folder, typo'd-then-corrected MX, bounced-and-fixed, etc).
  # The token and accept link are unchanged; we just refresh the validity
  # window so the invitee gets a full EXPIRY_WINDOW from this resend.
  def resend
    @invitation = @organization.invitations.find(params[:id])
    authorize @invitation

    unless @invitation.pending?
      redirect_to organization_memberships_path(@organization),
        alert: "That invitation has already been #{@invitation.status} and can't be re-sent."
      return
    end

    # A time-expired invite still carries status: pending (expiry is timestamp-
    # based, not an enum transition). The pending list and Resend button only
    # surface not-expired invites, and show/accept/decline all refuse expired
    # ones — keep resend consistent rather than silently reviving a dead invite.
    if @invitation.expired?
      redirect_to organization_memberships_path(@organization),
        alert: "That invitation has expired and can't be re-sent."
      return
    end

    @invitation.refresh_expiry!
    InvitationMailer.invite(@invitation).deliver_later
    redirect_to organization_memberships_path(@organization),
      notice: "Invitation re-sent to #{@invitation.email}."
  end

  # Public actions (token-based, no auth required)

  def show
    if @invitation.expired? || !@invitation.pending?
      # Clear any stale token from a prior flow so subsequent sign-ins don't
      # carry it forward.
      session.delete(:invitation_token)
      render :expired and return
    end

    # Store the token so after sign-in/sign-up/OAuth, we can auto-accept
    session[:invitation_token] = @invitation.token

    # Check if invitee already has an account
    @existing_user = User.find_by(email: @invitation.email)

    if current_user
      # Already logged in — redirect them to accept directly
      redirect_to accept_invitation_path(@invitation.token)
    end
  end

  def accept
    if @invitation.expired? || !@invitation.pending?
      session.delete(:invitation_token)
      redirect_to root_path, alert: "This invitation is no longer valid." and return
    end

    unless current_user
      session[:invitation_token] = @invitation.token
      redirect_to new_user_session_path, notice: "Please sign in or create an account to accept this invitation." and return
    end

    unless @invitation.organization.kept?
      session.delete(:invitation_token)
      redirect_to root_path, alert: "This organization is no longer active." and return
    end

    if @invitation.organization.membership_for(current_user)
      session.delete(:invitation_token)
      redirect_to organization_path(@invitation.organization), notice: "You are already a member of this organization." and return
    end

    unless current_user.email.casecmp(@invitation.email).zero?
      session.delete(:invitation_token)
      redirect_to root_path,
        alert: "This invitation was sent to #{@invitation.email}. Please sign in with that email to accept." and return
    end

    @invitation.accept!(current_user)
    session.delete(:invitation_token)

    redirect_to organization_path(@invitation.organization), notice: "You've joined #{@invitation.organization.name}!"
  end

  def decline
    if @invitation.expired? || !@invitation.pending?
      session.delete(:invitation_token)
      redirect_to root_path, alert: "This invitation is no longer valid." and return
    end

    # Declining voids the invite for everyone, so require the actor to prove they
    # own the invited address (same bar as accept). Otherwise anyone who obtains
    # the token URL (a forwarded email, a shared inbox) could permanently cancel
    # someone else's invitation.
    unless current_user
      session[:invitation_token] = @invitation.token
      redirect_to new_user_session_path,
        notice: "Please sign in to manage this invitation." and return
    end

    unless current_user.email.casecmp(@invitation.email).zero?
      session.delete(:invitation_token)
      redirect_to root_path,
        alert: "This invitation was sent to #{@invitation.email}. Please sign in with that email to manage it." and return
    end

    @invitation.decline!
    session.delete(:invitation_token)
    redirect_to root_path, notice: "Invitation declined."
  end

  private

  def set_organization
    @organization = policy_scope(Organization).find_by(id: params[:organization_id])
    redirect_to(authenticated_root_path, alert: "Organization not found.") and return unless @organization
  end

  def set_invitation_by_token
    @invitation = Invitation.find_by(token: params[:token])
    redirect_to(root_path, alert: "Invalid invitation link.") and return unless @invitation
  end

  def invitation_params
    inv = params.require(:invitation)
    role = inv.fetch(:role, nil).to_s
    raise ActionController::BadRequest, "Invalid role" unless Invitation.roles.key?(role)
    { email: inv[:email], role: role }
  end

  def skip_pundit?
    action_name.in?(%w[show accept decline])
  end
end

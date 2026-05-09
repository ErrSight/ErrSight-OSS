class InvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [ :show, :accept, :decline ]
  before_action :set_organization, only: [ :create, :destroy ]
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
    if @invitation.pending? && !@invitation.expired?
      @invitation.decline!
    end
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

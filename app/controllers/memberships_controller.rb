class MembershipsController < ApplicationController
  before_action :set_organization, except: :update_weekly_digest
  before_action :set_membership, only: [ :update, :destroy ]

  def index
    @memberships = @organization.memberships.includes(:user).order(created_at: :asc)
    @pending_invitations = @organization.invitations.pending.not_expired.order(created_at: :desc)
    @current_membership = @organization.membership_for(current_user)
    authorize Membership.new(organization: @organization), :index?
  end

  def update
    authorize @membership
    if @membership.update(membership_params)
      flash.now[:notice] = "Role updated to #{@membership.role.capitalize} for #{@membership.user.name.presence || @membership.user.email}."
      respond_to do |format|
        format.html { redirect_to organization_memberships_path(@organization), notice: flash.now[:notice] }
        format.turbo_stream
      end
    else
      redirect_to organization_memberships_path(@organization), alert: "Could not update role."
    end
  end

  def destroy
    authorize @membership
    removed_name = @membership.user.name.presence || @membership.user.email
    @membership.destroy
    flash.now[:notice] = "Removed #{removed_name} from #{@organization.name}."
    respond_to do |format|
      format.html { redirect_to organization_memberships_path(@organization), notice: flash.now[:notice] }
      format.turbo_stream
    end
  end

  # Self-serve toggle for the user's own weekly digest subscription.
  def update_weekly_digest
    membership = current_user.memberships.find(params[:id])
    enabled = ActiveModel::Type::Boolean.new.cast(params[:weekly_digest_enabled])
    membership.update_column(:weekly_digest_enabled, enabled)

    org_label = membership.organization&.name || "your organization"
    flash[:notice] = enabled ? "Weekly digest enabled for #{org_label}." :
                               "Weekly digest disabled for #{org_label}."
    redirect_to edit_user_registration_path
  end

  private

  def skip_pundit?
    action_name == "update_weekly_digest" || super
  end

  def set_organization
    @organization = policy_scope(Organization).find_by(id: params[:organization_id])
    redirect_to authenticated_root_path, alert: "Organization not found." unless @organization
  end

  def set_membership
    @membership = @organization.memberships.find(params[:id])
  end

  def membership_params
    role = params.require(:membership).fetch(:role, nil).to_s
    raise ActionController::BadRequest, "Invalid role" unless Membership.roles.key?(role)
    { role: role }
  end
end

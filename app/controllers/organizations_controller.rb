class OrganizationsController < ApplicationController
  before_action :set_organization, only: [ :show, :edit, :update, :slack_test ]

  def new
    @organization = Organization.new
    authorize @organization
  end

  def create
    @organization = Organization.new(organization_params.merge(owner: current_user))
    authorize @organization

    if @organization.save
      @organization.memberships.create!(user: current_user, role: :admin)
      redirect_to @organization, notice: "Organization created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @organization
    @projects = @organization.projects.order(created_at: :desc)
    @members = @organization.memberships.includes(:user).order(created_at: :asc)
    @pending_invitations = @organization.invitations.pending.not_expired.order(created_at: :desc)
    @membership = @organization.membership_for(current_user)
  end

  def edit
    authorize @organization
  end

  def update
    authorize @organization
    success_path = params[:return_to] == "alert_preferences" ? edit_alert_preference_path(@organization) : organization_path(@organization)
    if @organization.update(organization_params)
      redirect_to success_path, notice: "Organization updated successfully."
    elsif params[:return_to] == "alert_preferences"
      redirect_to edit_alert_preference_path(@organization), alert: @organization.errors.full_messages.to_sentence.presence || "Could not save."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # Switches the user's "current organization" context (session-scoped).
  # Used by the sidebar org picker. Only accepts orgs the user is a kept
  # member of — anything else 404s back to the root.
  def activate
    org = current_user.organizations.kept.find_by(id: params[:id])
    if org
      session[:current_organization_id] = org.id
      redirect_back fallback_location: organization_path(org), notice: "Switched to #{org.name}."
    else
      redirect_to authenticated_root_path, alert: "Organization not found."
    end
  end

  def slack_test
    authorize @organization, :update?

    unless @organization.slack_configured?
      redirect_to edit_alert_preference_path(@organization), alert: "Configure a Slack webhook first." and return
    end

    if SlackNotifier.post(@organization.slack_webhook_url, SlackNotifier.test_payload(@organization))
      redirect_to edit_alert_preference_path(@organization), notice: "Test message sent to Slack."
    else
      redirect_to edit_alert_preference_path(@organization), alert: "Slack webhook did not respond successfully. Check the URL."
    end
  end

  private

  # `activate` is a session-only context switch; the membership check inside
  # is the actual gate, so Pundit has nothing meaningful to authorize.
  def skip_pundit?
    action_name == "activate" || super
  end

  def set_organization
    @organization = policy_scope(Organization).find_by(id: params[:id])
    redirect_to authenticated_root_path, alert: "Organization not found." unless @organization
  end

  def organization_params
    params.require(:organization).permit(:name, :slack_webhook_url)
  end
end

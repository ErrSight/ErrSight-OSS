class AlertPreferencesController < ApplicationController
  before_action :set_membership_and_preference

  def edit
    authorize @organization, :show?
    @projects = @organization.projects.order(:name)
  end

  def update
    authorize @organization, :show?

    requested_project_id = params.dig(:alert_preference, :project_id)
    if requested_project_id.present?
      project = @organization.projects.find_by(id: requested_project_id)
      redirect_to(edit_alert_preference_path(@organization), alert: "Project not found.") and return unless project
      @preference = @membership.alert_preferences.find_or_initialize_by(project_id: project.id)
    end

    if @preference.update(preference_params)
      redirect_to edit_alert_preference_path(@organization), notice: "Alert preferences updated."
    else
      @projects = @organization.projects.order(:name)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_membership_and_preference
    @organization = policy_scope(Organization).find_by(id: params[:id])
    redirect_to authenticated_root_path, alert: "Organization not found." and return unless @organization

    @membership = @organization.membership_for(current_user)
    redirect_to @organization, alert: "You are not a member." and return unless @membership

    @preference = @membership.alert_preferences.find_or_initialize_by(project_id: nil)
  end

  def preference_params
    params.require(:alert_preference).permit(:email_enabled, :slack_enabled, :min_level, :digest_frequency)
  end

  def skip_pundit?
    true
  end
end

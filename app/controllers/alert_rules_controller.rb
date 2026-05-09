class AlertRulesController < ApplicationController
  before_action :set_project
  before_action :set_alert_rule, only: [ :edit, :update, :destroy ]

  def index
    authorize @project, :show?
    @alert_rules = @project.alert_rules.order(created_at: :desc)
  end

  def new
    authorize @project, :update?
    @alert_rule = @project.alert_rules.build(
      name: "New rule",
      rule_type: :every_event,
      level_threshold: Event.levels[:error],
      count_threshold: 1,
      window_seconds: 3600
    )
  end

  def create
    authorize @project, :update?
    @alert_rule = @project.alert_rules.build(alert_rule_params)
    if @alert_rule.save
      redirect_to project_alert_rules_path(@project), notice: "Alert rule created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project, :update?
  end

  def update
    authorize @project, :update?
    if @alert_rule.update(alert_rule_params)
      redirect_to project_alert_rules_path(@project), notice: "Alert rule updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @project, :update?
    @alert_rule.destroy
    redirect_to project_alert_rules_path(@project), notice: "Alert rule removed."
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  def set_alert_rule
    @alert_rule = @project.alert_rules.find_by(id: params[:id])
    redirect_to(project_alert_rules_path(@project), alert: "Rule not found.") and return unless @alert_rule
  end

  def alert_rule_params
    params.require(:alert_rule).permit(:name, :rule_type, :level_threshold,
                                       :count_threshold, :window_seconds, :active)
  end
end

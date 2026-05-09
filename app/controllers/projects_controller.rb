class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :destroy, :rotate_api_key, :time_series ]

  def index
    @projects = policy_scope(Project).order(created_at: :desc)
    authorize Project
  end

  def show
    authorize @project
    scope = EventRepository.filtered(
      project:     @project,
      environment: params[:environment],
      level:       params[:level]
    ).order(occurred_at: :desc)
    @pagy, @events = pagy(scope, items: 25)
    @environments = EventRepository.environments_for(@project)
    @unresolved_errors_count = EventRepository.unresolved_count_at_levels(
      project: @project,
      levels: [ Event.levels[:error], Event.levels[:fatal] ]
    )
  end

  def new
    @project = Project.new(organization_id: params[:organization_id] || current_organization&.id)
    authorize @project
  end

  def create
    @organization = current_user.organizations.kept.find_by(id: params[:project][:organization_id])
    unless @organization
      @project = Project.new(project_params)
      @project.errors.add(:organization_id, "must be selected")
      authorize @project
      render :new, status: :unprocessable_entity and return
    end

    @project = current_user.projects.build(project_params.merge(organization: @organization))
    authorize @project
    if @project.save
      redirect_to @project, notice: "Project created in #{@organization.name}."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project
  end

  def update
    authorize @project
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @project
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  def rotate_api_key
    authorize @project
    @project.rotate_default_api_key!
    redirect_to @project, notice: "API key rotated successfully."
  end

  def time_series
    authorize @project, :show?
    data = EventTimeSeries.for_project(
      @project,
      range:       params[:range],
      fingerprint: params[:fingerprint],
      environment: params[:environment]
    )
    render json: data
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:id])
    return if @project

    respond_to do |format|
      format.json { head :not_found }
      format.any  { redirect_to projects_path, alert: "Project not found." }
    end
  end

  def project_params
    permitted = [ :name, :rate_limit_per_minute ]
    permitted << :organization_id if action_name == "create"
    params.require(:project).permit(*permitted)
  end
end

class ApiKeysController < ApplicationController
  before_action :set_project
  before_action :set_api_key, only: [ :destroy ]

  def index
    authorize @project, :show?
    @api_keys    = @project.api_keys.order(revoked_at: :asc, created_at: :desc)
    @new_api_key = @project.api_keys.build(name: "", scope: :read)
    @just_created_token = flash[:new_api_key_token]
  end

  def create
    authorize @project, :update?
    @new_api_key = @project.api_keys.build(api_key_params)
    if @new_api_key.save
      redirect_to project_api_keys_path(@project),
                  notice: "API key created. Copy the token now — you won't see it again.",
                  flash: { new_api_key_token: @new_api_key.token }
    else
      @api_keys = @project.api_keys.order(created_at: :desc)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @project, :update?
    if default_api_key?(@api_key)
      redirect_to project_api_keys_path(@project),
                  alert: "Cannot revoke the default ingestion key. Rotate it from the project page instead."
      return
    end
    @api_key.revoke!
    redirect_to project_api_keys_path(@project), notice: "API key revoked."
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  def set_api_key
    @api_key = @project.api_keys.find_by(id: params[:id])
    redirect_to(project_api_keys_path(@project), alert: "API key not found.") and return unless @api_key
  end

  def api_key_params
    params.require(:api_key).permit(:name, :scope)
  end

  def default_api_key?(key)
    key.token == @project.api_key
  end
end

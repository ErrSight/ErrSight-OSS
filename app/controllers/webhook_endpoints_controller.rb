class WebhookEndpointsController < ApplicationController
  before_action :set_project
  before_action :set_webhook_endpoint, only: [ :edit, :update, :destroy ]

  def index
    authorize @project, :show?
    @webhook_endpoints = @project.webhook_endpoints.order(created_at: :desc)
  end

  def new
    authorize @project, :update?
    @webhook_endpoint = @project.webhook_endpoints.build
  end

  def create
    authorize @project, :update?
    @webhook_endpoint = @project.webhook_endpoints.build(webhook_endpoint_params)
    if @webhook_endpoint.save
      redirect_to project_webhook_endpoints_path(@project),
                  notice: "Webhook endpoint added. Its signing secret is shown below to project admins."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @project, :update?
  end

  def update
    authorize @project, :update?
    if @webhook_endpoint.update(webhook_endpoint_params)
      redirect_to project_webhook_endpoints_path(@project), notice: "Endpoint updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @project, :update?
    @webhook_endpoint.destroy
    redirect_to project_webhook_endpoints_path(@project), notice: "Endpoint removed."
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  def set_webhook_endpoint
    @webhook_endpoint = @project.webhook_endpoints.find_by(id: params[:id])
    redirect_to(project_webhook_endpoints_path(@project), alert: "Endpoint not found.") and return unless @webhook_endpoint
  end

  def webhook_endpoint_params
    params.require(:webhook_endpoint).permit(:url, :active)
  end
end

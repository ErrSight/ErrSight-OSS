class ProjectLogsChannel < ApplicationCable::Channel
  def subscribed
    project = Project.find_by(id: params[:project_id])
    if project && current_user.accessible_projects.exists?(project.id)
      stream_for project
    else
      reject
    end
  end
end

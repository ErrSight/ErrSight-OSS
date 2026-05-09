class IssuesController < ApplicationController
  before_action :set_project
  before_action :set_issue

  def show
    authorize @project, :show?
    @events = EventRepository.list_for_issue(project: @project, fingerprint: @issue.fingerprint, limit: 50)
    @comments = @issue.comments.includes(:user).chronological
    @assignable_users = @project.organization&.memberships&.includes(:user)&.map(&:user)&.compact || []
  end

  def update
    authorize @project, :triage_issues?
    if @issue.update(issue_params)
      redirect_to project_issue_path(@project, @issue.fingerprint), notice: "Issue updated."
    else
      redirect_to project_issue_path(@project, @issue.fingerprint), alert: @issue.errors.full_messages.to_sentence
    end
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  # Resolve by issue row first so an issue whose events have all been
  # retention-pruned is still viewable — comments and assignment survive
  # the prune and are sometimes the whole reason someone follows a
  # bookmarked URL here. Fall back to the events check so legacy events
  # that predate the issue aggregates table still resolve to a created
  # row. Redirect only when neither an issue row nor a backing event
  # exists for the fingerprint, so random fingerprints don't auto-create
  # empty issues.
  def set_issue
    fingerprint = params[:fingerprint] || params[:issue_fingerprint]
    return redirect_to(project_path(@project), alert: "Issue not found.") if fingerprint.blank?

    @issue = @project.issues.find_by(fingerprint: fingerprint)
    return if @issue

    if EventRepository.exists_for_fingerprint?(project: @project, fingerprint: fingerprint)
      @issue = Issue.find_or_init_by!(@project, fingerprint)
    else
      redirect_to project_path(@project), alert: "Issue not found."
    end
  end

  def issue_params
    permitted = params.require(:issue).permit(:assigned_to_id, :external_url)
    if permitted[:assigned_to_id].present? &&
       !@project.organization.memberships.exists?(user_id: permitted[:assigned_to_id])
      permitted[:assigned_to_id] = nil
    end
    permitted
  end
end

class IssueCommentsController < ApplicationController
  before_action :set_project
  before_action :set_issue

  def create
    authorize @project, :comment?
    # Lazily create the Issue row only after authorize. Doing this in a
    # before_action would let a viewer (who fails :comment? but passes the
    # project tenant check) trigger row creation just by hitting the endpoint.
    @issue ||= Issue.find_or_init_by!(@project, params[:issue_fingerprint])
    comment = @issue.comments.build(body: params.dig(:issue_comment, :body), user: current_user)
    if comment.save
      redirect_to project_issue_path(@project, @issue.fingerprint), notice: "Comment added."
    else
      redirect_to project_issue_path(@project, @issue.fingerprint), alert: comment.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @project, :comment?
    return redirect_to(project_path(@project), alert: "Comment not found.") unless @issue
    comment = @issue.comments.find_by(id: params[:id])
    return redirect_to(project_issue_path(@project, @issue.fingerprint), alert: "Comment not found.") unless comment
    unless can_destroy_comment?(comment)
      redirect_to(project_issue_path(@project, @issue.fingerprint), alert: "Not authorized.") and return
    end
    comment.destroy
    redirect_to project_issue_path(@project, @issue.fingerprint), notice: "Comment removed."
  end

  private

  # Author can always delete. Global admins and org admins can moderate —
  # this also covers orphaned comments whose author has been hard-deleted
  # (user_id IS NULL), which would otherwise be permanently unremovable.
  def can_destroy_comment?(comment)
    return true if comment.user_id.present? && comment.user_id == current_user.id
    return true if current_user.admin?
    @project.organization.membership_for(current_user)&.admin? || false
  end

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end

  # Read-only by design. The Issue row is only inserted in #create, after
  # `authorize @project, :comment?` has run.
  def set_issue
    fingerprint = params[:issue_fingerprint]
    if fingerprint.blank? ||
       !EventRepository.exists_for_fingerprint?(project: @project, fingerprint: fingerprint)
      redirect_to(project_path(@project), alert: "Issue not found.") and return
    end
    @issue = Issue.find_by(project: @project, fingerprint: fingerprint)
  end
end

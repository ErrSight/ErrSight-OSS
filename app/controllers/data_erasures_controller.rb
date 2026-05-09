class DataErasuresController < ApplicationController
  before_action :set_project

  def new
    authorize @project, :erase_user_data?
  end

  def create
    authorize @project, :erase_user_data?
    identifier = params[:user_identifier].to_s.strip
    if identifier.blank?
      redirect_to new_project_data_erasure_path(@project), alert: "Provide a user identifier."
      return
    end

    count, bytes = EventRepository.erase_by_user_identifier!(
      project_id: @project.id,
      user_identifier: identifier
    )

    if count.zero?
      redirect_to new_project_data_erasure_path(@project), alert: "No events found for that identifier."
      return
    end

    Project.where(id: @project.id).update_all([
      "events_count = GREATEST(events_count - ?, 0), " \
      "storage_bytes = GREATEST(storage_bytes - ?, 0), " \
      "updated_at = NOW()",
      count, bytes
    ])

    # Hash the identifier — it's typically a user email/id submitted for GDPR
    # erasure, so logging it verbatim would re-introduce the PII into log
    # infrastructure that DataErasure can't reach.
    identifier_hash = Digest::SHA256.hexdigest(identifier)[0, 12]
    Rails.logger.info "[DataErasure] project=#{@project.id} identifier_hash=#{identifier_hash} erased=#{count} bytes=#{bytes} actor=#{current_user.id}"
    redirect_to project_path(@project), notice: "Erased #{count} #{'event'.pluralize(count)}."
  end

  private

  def set_project
    @project = policy_scope(Project).find_by(id: params[:project_id])
    redirect_to(projects_path, alert: "Project not found.") and return unless @project
  end
end

class DashboardController < ApplicationController
  def index
    # Scope the dashboard to the user's currently-active organization (set via
    # the sidebar switcher). Without this, a multi-org user would see metrics
    # bleed across orgs and switching the picker would feel like a no-op.
    @organization = current_organization
    base = policy_scope(Project)
    @projects = (@organization ? base.where(organization_id: @organization.id) : base).order(created_at: :desc)
    @total_events = @projects.sum(:events_count)
    @recent_events = EventRepository.recent_across_projects(projects: @projects, limit: 10)
    authorize :dashboard, :index?
  end
end

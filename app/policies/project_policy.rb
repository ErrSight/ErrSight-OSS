class ProjectPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.where(organization_id: user.organizations.kept.select(:id))
      end
    end
  end

  def index?
    true
  end

  def show?
    org_viewer_or_above?
  end

  def create?
    true
  end

  def new?
    create?
  end

  def update?
    org_admin?
  end

  def edit?
    update?
  end

  def destroy?
    org_admin?
  end

  def rotate_api_key?
    org_admin?
  end

  def erase_user_data?
    org_admin?
  end

  def resolve_events?
    org_member_or_above?
  end

  def mute_events?
    org_member_or_above?
  end

  def triage_issues?
    org_member_or_above?
  end

  def comment?
    org_member_or_above?
  end

  private

  def record_organization
    record.organization
  end
end

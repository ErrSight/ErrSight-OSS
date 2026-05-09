class EventPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.admin?
        scope.all
      else
        scope.joins(:project).where(projects: { organization_id: user.organizations.kept.select(:id) })
      end
    end
  end

  def index?
    user.admin? || user.organizations.kept.exists?
  end

  def show?
    org_viewer_or_above?
  end

  def resolve?
    org_member_or_above?
  end

  def unresolve?
    org_member_or_above?
  end

  def destroy?
    org_admin?
  end

  private

  def record_organization
    record.project.organization
  end
end

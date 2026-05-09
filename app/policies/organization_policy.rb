class OrganizationPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  class Scope < ApplicationPolicy::Scope
    def resolve
      base = scope.kept
      if user.admin?
        base
      else
        base.joins(:memberships).where(memberships: { user_id: user.id })
      end
    end
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

  private

  def record_organization
    record
  end
end

class ApiKeyPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  def index?
    org_viewer_or_above?
  end

  def create?
    org_admin?
  end

  def destroy?
    org_admin?
  end

  private

  def record_organization
    record.is_a?(Class) ? nil : record.project.organization
  end
end

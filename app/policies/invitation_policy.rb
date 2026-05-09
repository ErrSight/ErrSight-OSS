class InvitationPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  def create?
    org_admin?
  end

  def destroy?
    org_admin?
  end

  def resend?
    org_admin?
  end

  private

  def record_organization
    record.organization
  end
end

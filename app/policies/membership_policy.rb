class MembershipPolicy < ApplicationPolicy
  include OrganizationRoleCheck

  def index?
    org_viewer_or_above?
  end

  def update?
    org_admin? && !last_admin? && !owner_membership?
  end

  def destroy?
    org_admin? && !last_admin? && !owner_membership?
  end

  private

  def record_organization
    record.organization
  end

  def last_admin?
    record.admin? && record.organization.memberships.admins.count == 1
  end

  # The org's owner_id is set to record.user — and Organization/Project
  # visibility is membership-based — so removing or demoting the owner's
  # membership leaves them as billing customer + owner_id while locking them
  # out of normal access. Block both paths at the policy layer; ownership
  # transfer needs its own explicit flow, not a side-effect of role mgmt.
  def owner_membership?
    record.user_id == record.organization.owner_id
  end
end

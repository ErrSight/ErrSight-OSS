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
    # `create?`/`new?` are also evaluated against the Project class (Pundit's
    # convention for "can this user reach the new/create form?") and against
    # org-less instances on the controller's "no org selected" error path. With
    # no org to scope a role to, stay permissive there.
    return true unless record.is_a?(Project) && record.organization

    # If the user isn't a member of the target org at all, defer to the
    # controller (it re-renders the form with a generic error, avoiding an
    # org-existence oracle). Only deny members whose role is too low: viewers
    # must not be able to create projects.
    membership.nil? || org_member_or_above?
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

module OrganizationRoleCheck
  private

  def membership
    @membership ||= record_organization&.membership_for(user)
  end

  def role
    membership&.role
  end

  def org_admin?
    user.admin? || role == "admin"
  end

  def org_member_or_above?
    user.admin? || role.in?(%w[admin member])
  end

  def org_viewer_or_above?
    user.admin? || membership.present?
  end
end

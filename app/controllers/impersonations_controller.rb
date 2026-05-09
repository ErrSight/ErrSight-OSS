class ImpersonationsController < ApplicationController
  def destroy
    admin_id = session.delete(:true_admin_id)
    admin = User.kept.find_by(id: admin_id) if admin_id

    unless admin&.admin?
      sign_out(:user)
      redirect_to new_user_session_path, alert: "Not impersonating." and return
    end

    Rails.logger.info "[impersonation] admin_id=#{admin.id} stopped impersonating user_id=#{current_user&.id}"
    bypass_sign_in(admin, scope: :user)
    redirect_to admin_root_path, notice: "Returned to admin account."
  end

  private

  def skip_pundit?
    true
  end
end

class Users::ConfirmationsController < Devise::ConfirmationsController
  # GET /users/confirmation?confirmation_token=...
  # Confirms the account, signs the user in, and lands them on the dashboard.
  def show
    self.resource = resource_class.confirm_by_token(params[:confirmation_token])
    yield resource if block_given?

    if resource.errors.empty?
      sign_in(resource_name, resource) unless user_signed_in?
      set_flash_message!(:notice, :confirmed)
      redirect_to after_confirmation_path_for(resource_name, resource)
    else
      respond_with_navigational(resource.errors, status: :unprocessable_entity) { render :new }
    end
  end

  protected

  def after_confirmation_path_for(_resource_name, resource)
    resource.active_for_authentication? ? authenticated_root_path : new_user_session_path
  end

  # On resend, keep them on the check-email page.
  def after_resending_confirmation_instructions_path_for(_resource_name)
    check_email_path(email: resource.email)
  end
end

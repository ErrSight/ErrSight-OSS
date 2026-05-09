class Users::RegistrationsController < Devise::RegistrationsController
  def create
    build_resource(sign_up_params.except(:organization_name))
    org_name = sign_up_params[:organization_name].to_s.strip

    resource_saved = false
    ActiveRecord::Base.transaction do
      resource_saved = resource.save
      if resource_saved
        # Skip the personal org when the user is signing up via an invite —
        # after_sign_up_path_for auto-accepts pending invites for this email,
        # so they'll join the team org directly.
        unless Invitation.pending_for_email(resource.email).exists?
          org = Organization.create!(
            name: org_name.presence || default_org_name(resource),
            owner: resource
          )
          org.memberships.create!(user: resource, role: :admin)
        end
      else
        raise ActiveRecord::Rollback
      end
    end

    yield resource if block_given?

    if resource_saved
      if resource.active_for_authentication?
        set_flash_message!(:notice, :signed_up)
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message!(:notice, :"signed_up_but_#{resource.inactive_message}")
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    else
      clean_up_passwords resource
      set_minimum_password_length
      respond_with resource
    end
  end

  # Soft-delete the account (Discard) instead of the Devise default hard-destroy.
  # Blocked if the user still owns a shared org with other members — they must
  # be removed first. Solo-owned orgs cascade via User#after_discard. A purge
  # job hard-deletes the user (and its discarded orgs) after User::RETENTION_WINDOW.
  def destroy
    if (blocker = account_deletion_blocker(resource))
      redirect_to edit_user_registration_path, alert: blocker and return
    end

    resource.discard!
    Devise.sign_out_all_scopes ? sign_out : sign_out(resource_name)
    flash[:notice] = "Your account has been scheduled for deletion. You have 90 days to recover it via support."
    yield resource if block_given?
    respond_with_navigational(resource) { redirect_to after_sign_out_path_for(resource_name) }
  end

  protected

  def sign_up_params
    params.require(:user).permit(:name, :email, :password, :password_confirmation, :organization_name)
  end

  # Unconfirmed users land on the "Check your email" page so they can resend
  # the confirmation if it doesn't arrive.
  def after_inactive_sign_up_path_for(resource)
    check_email_path(email: resource.try(:email))
  end

  private

  def default_org_name(user)
    base = user.name.presence || user.email.to_s.split("@").first
    "#{base}'s Organization"
  end

  # Returns nil if the user can delete their account, or a human-readable alert
  # string explaining the blocker.
  def account_deletion_blocker(user)
    shared = user.shared_owned_organizations
    if shared.any?
      names = shared.map(&:name).to_sentence
      return "You own #{shared.size == 1 ? 'an organization' : 'organizations'} (#{names}) with other members. " \
             "Remove all other members before deleting your account."
    end

    nil
  end
end

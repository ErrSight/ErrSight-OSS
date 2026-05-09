class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    omniauth_sign_in("Google")
  end

  def github
    omniauth_sign_in("GitHub")
  end

  def failure
    redirect_to new_user_session_url, alert: "Sign-in failed. Please try again."
  end

  private

  def omniauth_sign_in(provider_name)
    auth = request.env["omniauth.auth"]

    is_new_user = !user_already_exists?(auth)

    @user = User.from_omniauth(auth)

    if @user.discarded?
      redirect_to new_user_session_url, alert: "This account has been deleted."
      return
    end

    # Brand-new OAuth users get a default organization unless they have a
    # pending invitation (in which case after_sign_in_path_for auto-accepts
    # it and routes them into the existing team org).
    if is_new_user && !Invitation.pending_for_email(@user.email).exists?
      org = Organization.create!(
        name: "#{(@user.name.presence || @user.email.split('@').first)}'s Organization",
        owner: @user
      )
      org.memberships.create!(user: @user, role: :admin)
    end

    sign_in_and_redirect @user, event: :authentication
    set_flash_message(:notice, :success, kind: provider_name) if is_navigational_format?
  rescue ActiveRecord::RecordInvalid
    redirect_to new_user_registration_url, alert: "Could not sign in with #{provider_name}. Please try again."
  end

  def user_already_exists?(auth)
    provider = auth.provider.to_s
    uid      = auth.uid.to_s
    email    = auth.info.email.to_s.downcase

    User.exists?(provider: provider, uid: uid) ||
      (email.present? && User.exists?(email: email))
  end
end

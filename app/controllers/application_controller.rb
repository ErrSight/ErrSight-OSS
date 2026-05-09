class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  layout :layout_for_request

  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :authenticate_user!
  before_action :ensure_organization_exists!

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  helper_method :impersonating?, :true_admin, :current_organization, :public_signup_allowed?

  after_action :verify_authorized, unless: :skip_pundit_authorized?
  after_action :verify_policy_scoped, unless: :skip_pundit_scoped?

  private

  def layout_for_request
    if devise_controller? &&
       ((controller_name == "sessions" && action_name.in?(%w[new create])) ||
        (controller_name == "registrations" && action_name.in?(%w[new create])) ||
        (controller_name == "passwords" && action_name.in?(%w[new create])))
      "auth"
    else
      "application"
    end
  end

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back(fallback_location: root_path)
  end

  def skip_pundit?
    devise_controller? ||
      is_a?(ActiveAdmin::BaseController) ||
      mission_control_jobs_controller?
  end

  # mission_control-jobs mounts controllers that inherit from ::ApplicationController
  # (its `base_controller_class` default), so they pick up the Pundit
  # after_actions defined here. Their actions never call `policy_scope` /
  # `authorize`, so verify_policy_scoped raises after every render. The route
  # is already gated by `authenticated :user, ->(u) { u.admin? }` in routes.rb;
  # bypassing Pundit here just acknowledges that the engine has its own
  # implicit "admins-only" model.
  def mission_control_jobs_controller?
    defined?(MissionControl::Jobs::ApplicationController) &&
      is_a?(MissionControl::Jobs::ApplicationController)
  end

  def skip_pundit_authorized?
    skip_pundit? || action_name == "index"
  end

  def skip_pundit_scoped?
    skip_pundit? || action_name != "index"
  end

  def authenticate_admin!
    authenticate_user!
    redirect_to root_path, alert: "Admin access required." unless current_user&.admin?
  end

  # Authenticated users always need at least one kept organization to access
  # the app's main UI — every project, alert, invitation, and webhook hangs
  # off one. Signup auto-creates a personal org (registrations_controller and
  # omniauth_callbacks_controller both do this), but if that creation failed
  # or an admin discarded the only kept org out from under them, route them
  # back to the org-create form.
  def ensure_organization_exists!
    return unless current_user&.persisted?
    return if current_user.organizations.kept.any?

    return if controller_path == "organizations"          # listing / creating orgs
    return if controller_path == "invitations"            # accepting an invite creates membership
    return if controller_path == "pages"                  # docs, support, legal pages
    return if devise_controller?                          # sessions / registrations / passwords
    return if is_a?(ActiveAdmin::BaseController)
    return if mission_control_jobs_controller?

    redirect_to new_organization_path, notice: "Welcome! Create your first organization to get started."
  end

  def impersonating?
    session[:true_admin_id].present?
  end

  def true_admin
    return nil unless impersonating?
    @true_admin ||= User.kept.find_by(id: session[:true_admin_id])
  end

  # Invite-only by default. Opt back into open registration with
  # ALLOW_PUBLIC_SIGNUP=true. Read in three places: the registrations gate
  # (with session-token bypass for invitees), the OAuth callback gate (with
  # pending-invitation email check), and marketing-page CTAs.
  def public_signup_allowed?
    ENV["ALLOW_PUBLIC_SIGNUP"].to_s.downcase == "true"
  end

  # Session-scoped "active org" used by the sidebar picker and by defaults
  # like `+ New project`. Falls back to the user's primary org if the session
  # value is missing, stale, or for an org the user no longer belongs to.
  # Always returns a kept org the user is a member of, or nil.
  def current_organization
    return @current_organization if defined?(@current_organization)
    return @current_organization = nil unless current_user

    if (id = session[:current_organization_id])
      @current_organization = current_user.organizations.kept.find_by(id: id)
    end
    @current_organization ||= current_user.organizations.kept.first
  end

  def after_sign_up_path_for(resource)
    session.delete(:invitation_token)
    auto_accept_pending_invitations(resource)
    authenticated_root_path
  end

  def after_sign_in_path_for(resource)
    session.delete(:invitation_token)
    auto_accept_pending_invitations(resource)

    if resource.admin?
      admin_root_path
    else
      authenticated_root_path
    end
  end

  # Accepts every pending, unexpired invitation matching the user's email.
  # Idempotent (skips orgs the user is already a member of) and tolerant
  # (an invalid invite is logged but doesn't block sign-in).
  def auto_accept_pending_invitations(user)
    return if user.blank? || user.email.blank?

    Invitation.pending_for_email(user.email).find_each do |invite|
      next if invite.organization.membership_for(user)
      next unless invite.organization.kept?
      begin
        invite.accept!(user)
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn(
          "[auto_accept_pending_invitations] skipped invite=#{invite.id} " \
          "org=#{invite.organization_id} error=#{e.class}"
        )
        next
      end
    end
  end
end

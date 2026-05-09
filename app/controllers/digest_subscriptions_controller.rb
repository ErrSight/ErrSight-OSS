class DigestSubscriptionsController < ApplicationController
  # Public, token-based unsubscribe — no login required.
  skip_before_action :authenticate_user!
  skip_forgery_protection only: :destroy

  def destroy
    @membership = Membership.find_by_digest_unsubscribe_token(params[:token])

    if @membership
      @membership.update_column(:weekly_digest_enabled, false)
      @organization_name = @membership.organization.name
    end

    render :destroy
  end

  private

  def skip_pundit?
    true
  end
end

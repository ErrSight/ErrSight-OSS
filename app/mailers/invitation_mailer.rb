class InvitationMailer < ApplicationMailer
  def invite(invitation)
    @invitation = invitation
    @organization = invitation.organization
    @inviter = invitation.invited_by
    @accept_url = invitation_show_url(invitation.token)

    mail(
      to: invitation.email,
      subject: "[ErrSight · #{@organization.name}] You're invited to join the team"
    )
  end
end

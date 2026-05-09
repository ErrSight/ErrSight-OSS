require "test_helper"

class InvitationMailerTest < ActionMailer::TestCase
  setup do
    @org = organizations(:regular_org)
    @inviter = users(:regular)
    @invitation = @org.invitations.create!(
      email: "newperson@example.com",
      role: :member,
      invited_by: @inviter
    )
  end

  test "invite is addressed to the invitee" do
    mail = InvitationMailer.invite(@invitation)
    assert_equal [ @invitation.email ], mail.to
    assert_match @org.name, mail.subject
    assert_match "invited", mail.subject
  end

  test "invite body contains the accept URL with the invitation token" do
    mail = InvitationMailer.invite(@invitation)
    assert_match @invitation.token, mail.text_part.decoded
    assert_match @invitation.token, mail.html_part.decoded
  end
end

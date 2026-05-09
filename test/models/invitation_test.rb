require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  setup do
    @org    = organizations(:team_org)
    @owner  = users(:team_owner)
  end

  # ── Email normalization ─────────────────────────────────────────────────────
  #
  # Pre-fix, the email column held whatever case the inviter typed. The
  # uniqueness validator and InvitationsController#show#find_by(email:) both
  # compared exact case, while pending_for_email used LOWER(email) — so the
  # same logical address could branch four different ways across one feature.

  test "downcases email on save" do
    invite = @org.invitations.create!(email: "Foo@Example.COM", role: :member, invited_by: @owner)
    assert_equal "foo@example.com", invite.reload.email
  end

  test "strips surrounding whitespace on save" do
    invite = @org.invitations.create!(email: "  bar@example.com  ", role: :member, invited_by: @owner)
    assert_equal "bar@example.com", invite.reload.email
  end

  test "uniqueness validator now treats mixed-case duplicates as duplicates" do
    @org.invitations.create!(email: "dup@example.com", role: :member, invited_by: @owner)

    dup = @org.invitations.build(email: "DUP@Example.COM", role: :member, invited_by: @owner)
    assert_not dup.valid?
    assert_match(/already been invited/i, dup.errors[:email].to_sentence)
  end

  test "pending_for_email matches regardless of inviter's casing" do
    invite = @org.invitations.create!(email: "Mixed@Example.com", role: :member, invited_by: @owner)
    assert_includes Invitation.pending_for_email("mixed@example.com"), invite
    assert_includes Invitation.pending_for_email("MIXED@EXAMPLE.COM"), invite
  end
end

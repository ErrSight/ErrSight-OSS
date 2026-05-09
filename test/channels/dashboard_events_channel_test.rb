require "test_helper"

class DashboardEventsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user        = users(:regular)
    @own_org     = organizations(:regular_org)
    @foreign_org = organizations(:admin_org)
    stub_connection(current_user: @user)
  end

  test "subscribes and streams for an org the user is a member of" do
    subscribe(organization_id: @own_org.id)

    assert subscription.confirmed?
    assert_has_stream_for @own_org
  end

  # The cross-tenant guard. Without the membership check, any authenticated
  # user could subscribe to any org's live event stream by guessing IDs.
  test "rejects subscription to an org the user is not a member of" do
    subscribe(organization_id: @foreign_org.id)

    assert subscription.rejected?
  end

  test "rejects subscription when organization_id is missing" do
    subscribe

    assert subscription.rejected?
  end

  test "rejects subscription when organization_id does not exist" do
    subscribe(organization_id: 0)

    assert subscription.rejected?
  end

  test "rejects subscription when membership belongs to a discarded org" do
    @own_org.discard
    subscribe(organization_id: @own_org.id)

    assert subscription.rejected?
  end

  # Multi-org guard: a user who belongs to two orgs must be able to subscribe
  # to whichever one they're currently viewing — not just their oldest
  # (primary) one. Pre-fix this streamed for primary_organization regardless
  # of the requested org, so events from the secondary org never arrived and
  # primary-org events leaked into the secondary's dashboard.
  test "multi-org user can subscribe to a non-primary org and streams for the requested one" do
    secondary = Organization.create!(name: "Secondary", owner: @user, plan: "free")
    Membership.create!(organization: secondary, user: @user, role: :admin)

    subscribe(organization_id: secondary.id)

    assert subscription.confirmed?
    assert_has_stream_for secondary
    assert_no_streams_for @own_org
  end

  test "user removed from an org cannot subscribe to it" do
    member = users(:member_user)
    team   = organizations(:team_org)
    stub_connection(current_user: member)

    subscribe(organization_id: team.id)
    assert subscription.confirmed?

    unsubscribe
    member.memberships.find_by(organization: team).destroy

    subscribe(organization_id: team.id)
    assert subscription.rejected?
  end

  private

  # ActionCable channel test cases expose `assert_has_stream_for` but not its
  # negative. Reach into the subscription's registered streams directly.
  def assert_no_streams_for(model)
    stream_name = self.class.channel_class.broadcasting_for(model)
    assert_not_includes subscription.streams, stream_name,
      "expected no stream for #{model.inspect}, got #{subscription.streams.inspect}"
  end
end

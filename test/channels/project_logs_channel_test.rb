require "test_helper"

class ProjectLogsChannelTest < ActionCable::Channel::TestCase
  setup do
    @user            = users(:regular)
    @own_project     = projects(:alpha)
    @foreign_project = projects(:admin_project)
    stub_connection(current_user: @user)
  end

  test "subscribes and streams for a project the user can access" do
    subscribe(project_id: @own_project.id)

    assert subscription.confirmed?
    assert_has_stream_for @own_project
  end

  # The cross-tenant guard. Without the accessible_projects check, anyone with
  # a session could subscribe to any project's live event stream by guessing IDs.
  test "rejects subscription to a project from another organization" do
    subscribe(project_id: @foreign_project.id)

    assert subscription.rejected?
  end

  test "rejects subscription when project_id is missing" do
    subscribe

    assert subscription.rejected?
  end

  test "rejects subscription when project_id does not exist" do
    subscribe(project_id: 0)

    assert subscription.rejected?
  end
end

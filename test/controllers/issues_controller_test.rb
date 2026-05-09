require "test_helper"

class IssuesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    @event   = events(:error_event)
    sign_in @user
  end

  test "GET /projects/:id/issues/:fingerprint returns success" do
    get project_issue_path(@project, @event.fingerprint)
    assert_response :success
  end

  test "GET /projects/:id/issues/:fingerprint 404s into redirect when no events match" do
    get project_issue_path(@project, "nonexistent-fp")
    assert_redirected_to project_path(@project)
  end

  test "GET /projects/:id/issues/:fingerprint renders when issue row survives a full event prune" do
    # User-reported flow: events for an issue age out under retention; the
    # in-job reconcile zeros the aggregates so it leaves the groups list,
    # but the issue row sticks around (comments / assignment intact). A
    # bookmarked / shared URL should still resolve.
    event = @project.events.create!(
      level: :error, message: "doomed", fingerprint: "fp-retained",
      occurred_at: 1.hour.ago, size_bytes: 100
    )
    issue = Issue.find_by!(project: @project, fingerprint: "fp-retained")
    issue.comments.create!(user: @user, body: "We saw this last release.")
    Event.where(id: event.id).delete_all
    Issue.reconcile_aggregates_for_fingerprints!(
      project_id: @project.id, fingerprints: [ "fp-retained" ]
    )

    get project_issue_path(@project, "fp-retained")
    assert_response :success
    assert_match "We saw this last release.", response.body
  end

  test "PATCH updates assignee" do
    patch project_issue_path(@project, @event.fingerprint),
      params: { issue: { assigned_to_id: @user.id } }
    assert_redirected_to project_issue_path(@project, @event.fingerprint)
    assert_equal @user.id, Issue.find_by(project: @project, fingerprint: @event.fingerprint).assigned_to_id
  end

  test "PATCH updates external_url" do
    patch project_issue_path(@project, @event.fingerprint),
      params: { issue: { external_url: "https://github.com/acme/app/issues/1" } }
    assert_equal "https://github.com/acme/app/issues/1",
                 Issue.find_by(project: @project, fingerprint: @event.fingerprint).external_url
  end

  test "POST comment creates it" do
    assert_difference "IssueComment.count", 1 do
      post project_issue_comments_path(@project, @event.fingerprint),
        params: { issue_comment: { body: "First thoughts" } }
    end
  end

  test "non-admin member cannot delete another user's comment" do
    sign_out @user
    sign_in users(:member_user)

    project = projects(:team_project)
    project.events.create!(
      level: :error, message: "x", fingerprint: "moderation-fp",
      occurred_at: Time.current, size_bytes: 100
    )
    issue = Issue.find_or_init_by!(project, "moderation-fp")
    other_comment = issue.comments.create!(user: users(:team_owner), body: "theirs")

    assert_no_difference "IssueComment.count" do
      delete project_issue_comment_path(project, "moderation-fp", other_comment)
    end
  end

  test "org admin can moderate another user's comment" do
    issue = Issue.find_or_init_by!(@project, @event.fingerprint)
    other_comment = issue.comments.create!(user: users(:admin), body: "theirs")

    assert_difference "IssueComment.count", -1 do
      delete project_issue_comment_path(@project, @event.fingerprint, other_comment)
    end
  end

  test "user can delete their own comment" do
    issue = Issue.find_or_init_by!(@project, @event.fingerprint)
    mine  = issue.comments.create!(user: @user, body: "mine")

    assert_difference "IssueComment.count", -1 do
      delete project_issue_comment_path(@project, @event.fingerprint, mine)
    end
  end

  test "cannot access issues on another user's project" do
    get project_issue_path(projects(:admin_project), "any-fp")
    assert_redirected_to projects_path
  end

  # IDOR guard: regular user from regular_org must not be able to DELETE
  # a comment that lives under admin_org's project, even by knowing both
  # the project id and the comment id.
  test "outsider cannot delete a comment on another org's project" do
    other_project = projects(:admin_project)
    fingerprint = "cross-org-comment-fp"
    other_project.events.create!(
      level: :error, message: "x", fingerprint: fingerprint,
      occurred_at: Time.current, size_bytes: 100
    )
    issue = Issue.find_or_init_by!(other_project, fingerprint)
    other_comment = issue.comments.create!(user: users(:admin), body: "admin's comment")

    assert_no_difference "IssueComment.count" do
      delete project_issue_comment_path(other_project, fingerprint, other_comment)
    end
    assert_redirected_to projects_path
  end

  # Regression: previously `set_issue` ran `find_or_create_by!` in a
  # before_action, *before* `authorize @project, :comment?`. A viewer (who
  # passes the project tenant check but fails :comment?) could trigger an
  # Issue row insert just by hitting the endpoint. Now creation is gated by
  # authorize, so an unauthorized POST must not produce a row.
  test "POST comment by a viewer does not create an Issue row before authorize runs" do
    sign_out @user
    viewer  = users(:viewer_user)
    project = projects(:team_project)
    fingerprint = "viewer-no-create-fp"
    project.events.create!(
      level: :error, message: "x", fingerprint: fingerprint,
      occurred_at: Time.current, size_bytes: 100
    )

    sign_in viewer

    assert_no_difference "Issue.count" do
      assert_no_difference "IssueComment.count" do
        post project_issue_comments_path(project, fingerprint),
          params: { issue_comment: { body: "shouldn't land" } }
      end
    end
  end
end

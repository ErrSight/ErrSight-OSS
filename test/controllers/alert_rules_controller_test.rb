require "test_helper"

class AlertRulesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin    = users(:team_owner)
    @member   = users(:member_user)
    @viewer   = users(:viewer_user)
    @outsider = users(:over_limit)
    @project  = projects(:team_project)
  end

  def rule_params(overrides = {})
    {
      alert_rule: {
        name:            "Critical errors",
        rule_type:       "every_event",
        level_threshold: Event.levels[:error],
        count_threshold: 1,
        window_seconds:  3600,
        active:          true
      }.merge(overrides)
    }
  end

  test "unauthenticated user redirected" do
    get project_alert_rules_path(@project)
    assert_redirected_to new_user_session_path
  end

  test "outsider cannot access another org's rules" do
    sign_in @outsider
    get project_alert_rules_path(@project)
    assert_redirected_to projects_path
  end

  test "viewer can view index" do
    sign_in @viewer
    get project_alert_rules_path(@project)
    assert_response :success
  end

  test "viewer cannot create" do
    sign_in @viewer
    assert_no_difference -> { @project.alert_rules.count } do
      post project_alert_rules_path(@project), params: rule_params
    end
    assert_response :redirect
    assert_match(/not authorized/i, flash[:alert])
  end

  test "member cannot create (update? requires admin)" do
    sign_in @member
    assert_no_difference -> { @project.alert_rules.count } do
      post project_alert_rules_path(@project), params: rule_params
    end
    assert_response :redirect
  end

  test "admin can create" do
    sign_in @admin
    assert_difference -> { @project.alert_rules.count }, 1 do
      post project_alert_rules_path(@project), params: rule_params
    end
    assert_redirected_to project_alert_rules_path(@project)
  end

  test "admin can update" do
    sign_in @admin
    rule = @project.alert_rules.create!(
      name: "old", rule_type: :every_event, level_threshold: Event.levels[:error],
      count_threshold: 1, window_seconds: 3600
    )
    patch project_alert_rule_path(@project, rule),
          params: rule_params(name: "updated-name")
    assert_redirected_to project_alert_rules_path(@project)
    assert_equal "updated-name", rule.reload.name
  end

  test "admin can destroy" do
    sign_in @admin
    rule = @project.alert_rules.create!(
      name: "doomed", rule_type: :every_event, level_threshold: Event.levels[:error],
      count_threshold: 1, window_seconds: 3600
    )
    assert_difference -> { @project.alert_rules.count }, -1 do
      delete project_alert_rule_path(@project, rule)
    end
    assert_redirected_to project_alert_rules_path(@project)
  end
end

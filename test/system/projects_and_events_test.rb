require "application_system_test_case"

class ProjectsAndEventsTest < ApplicationSystemTestCase
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    @event   = events(:error_event)
    sign_in_as(@user)
  end

  test "signed-in user sees their projects on the projects index" do
    visit projects_path

    assert_text @project.name
    assert_text projects(:beta).name
    assert_no_text projects(:admin_project).name
  end

  test "opening a project from the index lands on the project page with the API key" do
    visit projects_path
    click_link @project.name

    assert_current_path project_path(@project)
    assert_text @project.name
    assert_text "X-API-Key"
    assert_text @project.api_key
  end

  test "events index renders unresolved events and hides resolved/discarded ones" do
    visit project_events_path(@project)

    assert_text "Events"
    assert_text @event.message
    assert_text events(:staging_event).message
    assert_no_text events(:resolved_event).message
    assert_no_text events(:discarded_event).message
  end

  test "filtering the events index by level via the facet rail updates the rows" do
    # Layout B exposes the faceted rail (level / status / environment).
    visit project_events_path(@project, layout: "b")

    assert_text @event.message
    assert_text events(:staging_event).message

    within ".es-facets" do
      click_on "warning"
    end

    assert_no_text @event.message
    assert_text events(:staging_event).message
  end

  test "the Resolved saved view surfaces resolved events" do
    visit project_events_path(@project)

    assert_no_text events(:resolved_event).message

    click_on "Resolved" # saved-view tab in the header strip

    assert_text events(:resolved_event).message
  end

  test "dashboard renders the recent events feed for the signed-in user" do
    visit dashboard_path

    assert_text "Dashboard"
    assert_text "Regular Org"
    assert_text @project.name
    assert_text @event.message.first(20)
  end
end

require "application_system_test_case"

# Drives the sidebar org + project switchers (dropdown_controller.js). The
# popover open/close and org-switching are client-side, so they belong in the
# system suite.
class SidebarSwitchersTest < ApplicationSystemTestCase
  setup do
    @user = users(:regular)
    @org2 = Organization.create!(name: "Second Switcher Co", owner: @user)
    Membership.create!(organization: @org2, user: @user, role: :admin)
    sign_in_as(@user)
  end

  test "org switcher opens and lists the user's organizations" do
    visit dashboard_path
    assert_no_text "Second Switcher Co"      # popover starts closed (hidden)
    find(".sb-orgswitch-trigger").click
    assert_text "Second Switcher Co"         # popover open, lists the other org
  end

  test "selecting an org from the switcher activates it and returns to the dashboard" do
    visit dashboard_path
    find(".sb-orgswitch-trigger").click
    within(".sb-org-popover") { click_button "Second Switcher Co" }

    assert_current_path dashboard_path
    assert_selector ".sb-orgswitch-name", text: "Second Switcher Co"
  end

  test "project switcher opens and lists the org's projects" do
    project = projects(:alpha)
    visit groups_project_events_path(project)
    find(".sb-projswitch-trigger").click

    assert_selector ".sb-proj-popover"
    assert_text project.name
  end
end

require "application_system_test_case"

# Drives the issue-detail slide-in overlay (overlay_controller.js + the Turbo
# Frame). Only a real browser exercises the open/close behaviour, so this lives
# in the system suite.
class IssueOverlayTest < ApplicationSystemTestCase
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    @event   = events(:error_event)
    sign_in_as(@user)
  end

  def open_overlay
    visit groups_project_events_path(@project)
    find(".iss-row", match: :first).click
    assert_selector ".iss-overlay.is-open"
  end

  test "clicking an issue row opens the detail overlay" do
    open_overlay
    assert_text "STACK TRACE"          # overlay content rendered into the frame
  end

  test "Escape closes the overlay" do
    open_overlay
    find("body").send_keys(:escape)
    assert_no_selector ".iss-overlay.is-open"
  end

  test "the close button dismisses the overlay" do
    open_overlay
    find("button[aria-label='Close overlay']").click
    assert_no_selector ".iss-overlay.is-open"
  end
end

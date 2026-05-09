require "test_helper"

class EventsExportTest < ActionDispatch::IntegrationTest
  setup do
    @user    = users(:regular)
    @project = projects(:alpha)
    sign_in @user
  end

  test "GET export.csv returns CSV attachment with headers" do
    get export_project_events_path(@project, format: :csv)
    assert_response :success
    assert_match "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"].to_s, "attachment"
    header = response.body.lines.first.to_s
    assert_match "id,occurred_at,level,message,environment", header
  end

  test "GET export.csv rows include kept events and exclude discarded" do
    get export_project_events_path(@project, format: :csv)
    body = response.body
    assert_match events(:error_event).fingerprint, body
    assert_no_match(/jkl012jkl012jkl0/, body) # discarded fixture
  end

  test "GET export.json returns JSON attachment" do
    get export_project_events_path(@project, format: :json)
    assert_response :success
    assert_match "application/json", response.media_type
    parsed = JSON.parse(response.body)
    assert parsed.is_a?(Array)
    assert parsed.any? { |row| row["fingerprint"] == events(:error_event).fingerprint }
  end

  test "export respects level filter" do
    get export_project_events_path(@project, format: :csv, level: "error")
    body = response.body.lines[1..] || []
    levels = body.filter_map { |line| line.split(",")[2] }.uniq
    assert_equal [ "error" ], levels unless body.empty?
  end

  test "cannot export for a project the user does not own" do
    get export_project_events_path(projects(:admin_project), format: :csv)
    assert_redirected_to projects_path
  end

  # Regression: pre-fix, the export used find_each, which silently overrides
  # any custom ORDER BY with primary-key ASC. So an export advertised as
  # newest-first actually streamed oldest-first by id. Insert three events
  # with occurred_at in NON-monotonic order vs. id, then verify CSV rows come
  # back in occurred_at DESC order — not id ASC.
  test "CSV export rows are ordered newest-first by occurred_at, not by id" do
    @project.events.delete_all  # drop fixture noise so the assertion is precise

    middle = @project.events.create!(message: "middle", level: :info, occurred_at: 5.minutes.ago,  size_bytes: 100)
    oldest = @project.events.create!(message: "oldest", level: :info, occurred_at: 2.hours.ago,    size_bytes: 100)
    newest = @project.events.create!(message: "newest", level: :info, occurred_at: 30.seconds.ago, size_bytes: 100)

    get export_project_events_path(@project, format: :csv)
    assert_response :success

    rows = CSV.parse(response.body, headers: true)
    ids  = rows["id"].map(&:to_i)

    assert_equal [ newest.id, middle.id, oldest.id ], ids,
                 "expected newest-first by occurred_at, got #{ids.inspect}"
  end

  test "JSON export rows are ordered newest-first by occurred_at, not by id" do
    @project.events.delete_all

    middle = @project.events.create!(message: "middle", level: :info, occurred_at: 5.minutes.ago,  size_bytes: 100)
    oldest = @project.events.create!(message: "oldest", level: :info, occurred_at: 2.hours.ago,    size_bytes: 100)
    newest = @project.events.create!(message: "newest", level: :info, occurred_at: 30.seconds.ago, size_bytes: 100)

    get export_project_events_path(@project, format: :json)
    assert_response :success

    ids = JSON.parse(response.body).map { |r| r["id"] }
    assert_equal [ newest.id, middle.id, oldest.id ], ids
  end
end

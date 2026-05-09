require "test_helper"

class IssueTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "unique per (project, fingerprint)" do
    Issue.create!(project: @project, fingerprint: "uniq-fp")
    dup = Issue.new(project: @project, fingerprint: "uniq-fp")
    assert_not dup.valid?
  end

  test "rejects invalid external_url" do
    issue = Issue.new(project: @project, fingerprint: "fp", external_url: "notaurl")
    assert_not issue.valid?
  end

  test "accepts http(s) external_url" do
    issue = Issue.new(project: @project, fingerprint: "fp", external_url: "https://github.com/x/y/issues/1")
    assert issue.valid?
  end

  test "find_or_init_by! returns existing record when already present" do
    Issue.create!(project: @project, fingerprint: "xx")
    assert_no_difference "Issue.count" do
      Issue.find_or_init_by!(@project, "xx")
    end
  end
end

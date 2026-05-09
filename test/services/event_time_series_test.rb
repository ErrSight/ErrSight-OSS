require "test_helper"

class EventTimeSeriesTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "returns empty buckets when project has no events in range" do
    @project.events.delete_all
    data = EventTimeSeries.for_project(@project, range: "24h")
    assert_equal 0, data[:total]
    assert data[:buckets].all? { |b| b[:count] == 0 }
  end

  test "buckets events by hour for 24h range" do
    @project.events.delete_all
    freeze_time do
      @project.events.create!(level: "error", message: "a", environment: "production",
                              fingerprint: "fp", occurred_at: 2.hours.ago, size_bytes: 100)
      @project.events.create!(level: "error", message: "b", environment: "production",
                              fingerprint: "fp", occurred_at: 2.hours.ago, size_bytes: 100)
      @project.events.create!(level: "info",  message: "c", environment: "production",
                              fingerprint: "fp", occurred_at: 5.hours.ago, size_bytes: 100)

      data = EventTimeSeries.for_project(@project, range: "24h")
      assert_equal 3, data[:total]
      counts = data[:buckets].map { |b| b[:count] }
      assert counts.sum == 3
      assert_equal 24, data[:buckets].size
    end
  end

  test "filters by fingerprint" do
    @project.events.delete_all
    @project.events.create!(level: "error", message: "a", environment: "production",
                            fingerprint: "target", occurred_at: 1.hour.ago, size_bytes: 100)
    @project.events.create!(level: "error", message: "b", environment: "production",
                            fingerprint: "other", occurred_at: 1.hour.ago, size_bytes: 100)

    data = EventTimeSeries.for_project(@project, range: "24h", fingerprint: "target")
    assert_equal 1, data[:total]
  end

  test "groups by day for 7d range" do
    data = EventTimeSeries.for_project(@project, range: "7d")
    assert_equal 7, data[:buckets].size
  end

  test "excludes discarded events" do
    @project.events.delete_all
    e = @project.events.create!(level: "error", message: "a", environment: "production",
                                fingerprint: "fp", occurred_at: 1.hour.ago, size_bytes: 100)
    e.discard

    data = EventTimeSeries.for_project(@project, range: "24h")
    assert_equal 0, data[:total]
  end
end

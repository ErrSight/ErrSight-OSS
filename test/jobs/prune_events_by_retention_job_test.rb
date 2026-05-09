require "test_helper"

class PruneEventsByRetentionJobTest < ActiveJob::TestCase
  setup do
    @project = projects(:alpha)
    Event.delete_all
  end

  test "no-op when RETENTION_DAYS=0 (pruning disabled)" do
    with_env("RETENTION_DAYS" => "0") do
      stale = @project.events.create!(
        level: "error", message: "old", occurred_at: 60.days.ago
      )
      PruneEventsByRetentionJob.new.perform
      assert Event.exists?(id: stale.id)
    end
  end

  test "deletes events older than RETENTION_DAYS" do
    with_env("RETENTION_DAYS" => "30") do
      stale  = @project.events.create!(level: "error", message: "stale",  occurred_at: 60.days.ago)
      recent = @project.events.create!(level: "error", message: "recent", occurred_at: 5.days.ago)

      PruneEventsByRetentionJob.new.perform

      assert_not Event.exists?(id: stale.id)
      assert     Event.exists?(id: recent.id)
    end
  end

  test "decrements project counters by the pruned bytes/count" do
    with_env("RETENTION_DAYS" => "30") do
      @project.events.create!(level: "error", message: "stale", occurred_at: 60.days.ago, size_bytes: 100)
      @project.update_columns(events_count: 1, storage_bytes: 100)

      PruneEventsByRetentionJob.new.perform

      @project.reload
      assert_equal 0, @project.events_count
      assert_equal 0, @project.storage_bytes
    end
  end

  private

  def with_env(overrides)
    saved = overrides.keys.to_h { |k| [ k, ENV[k] ] }
    overrides.each { |k, v| ENV[k] = v }
    yield
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end
end

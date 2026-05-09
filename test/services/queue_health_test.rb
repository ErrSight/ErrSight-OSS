require "test_helper"

class QueueHealthTest < ActiveSupport::TestCase
  setup do
    # Solid Queue's after_create on Job creates a ReadyExecution, so deleting
    # both is enough — there's nothing to leak in from earlier tests.
    SolidQueue::ReadyExecution.delete_all
    SolidQueue::FailedExecution.delete_all
    SolidQueue::Job.delete_all
  end

  test "snapshot returns zeros when the queue is empty" do
    s = QueueHealth.snapshot
    assert_equal 0, s.backlog
    assert_equal 0, s.oldest_ready_age_seconds
    assert_equal 0, s.failed
  end

  test "snapshot reports backlog as the number of ready executions" do
    3.times { enqueue_ready_job(at: Time.current) }
    assert_equal 3, QueueHealth.snapshot.backlog
  end

  test "snapshot reports the age of the oldest ready execution in seconds" do
    enqueue_ready_job(at: 90.seconds.ago)
    enqueue_ready_job(at: 30.seconds.ago)

    age = QueueHealth.snapshot.oldest_ready_age_seconds
    # Allow a couple seconds of slack for test runtime.
    assert_in_delta 90, age, 3
  end

  test "snapshot reports failed_executions count" do
    job = SolidQueue::Job.create!(class_name: "ProcessEventJob", queue_name: "events", arguments: "[]")
    # The after_create on Job spawns a ReadyExecution; consume it before
    # creating the FailedExecution so the unique (job_id) index isn't tripped.
    job.ready_execution.destroy
    SolidQueue::FailedExecution.create!(job_id: job.id, error: { class: "X", message: "y" })
    assert_equal 1, QueueHealth.snapshot.failed
  end

  private

  # Solid Queue's Job#after_create automatically spawns a ReadyExecution.
  # We can't pass created_at to it, so we backdate the row after the fact.
  def enqueue_ready_job(at:)
    job = SolidQueue::Job.create!(
      class_name: "ProcessEventJob",
      queue_name: "events",
      arguments: "[]"
    )
    job.ready_execution.update_columns(created_at: at)
    job
  end
end

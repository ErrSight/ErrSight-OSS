require "test_helper"

class ReportQueueHealthJobTest < ActiveJob::TestCase
  Snapshot = QueueHealth::Snapshot

  test "logs the snapshot at INFO when both signals are below the warn thresholds" do
    log = capture_log do
      with_snapshot(Snapshot.new(backlog: 100, oldest_ready_age_seconds: 5, failed: 0)) do
        ReportQueueHealthJob.new.perform
      end
    end
    assert_match(/INFO.*\[QueueHealth\] backlog=100 oldest_ready_age_s=5 failed=0/, log)
  end

  test "logs at WARN when backlog crosses the warn threshold" do
    log = capture_log do
      with_snapshot(Snapshot.new(backlog: 1_500, oldest_ready_age_seconds: 5, failed: 0)) do
        ReportQueueHealthJob.new.perform
      end
    end
    assert_match(/WARN.*backlog=1500/, log)
  end

  test "logs at WARN when oldest ready age crosses the warn threshold" do
    log = capture_log do
      with_snapshot(Snapshot.new(backlog: 50, oldest_ready_age_seconds: 90, failed: 0)) do
        ReportQueueHealthJob.new.perform
      end
    end
    assert_match(/WARN.*oldest_ready_age_s=90/, log)
  end

  test "escalates to ERROR when backlog crosses the crit threshold" do
    log = capture_log do
      with_snapshot(Snapshot.new(backlog: 12_000, oldest_ready_age_seconds: 5, failed: 0)) do
        ReportQueueHealthJob.new.perform
      end
    end
    assert_match(/ERROR.*backlog=12000/, log)
  end

  test "escalates to ERROR when oldest ready age crosses the crit threshold" do
    log = capture_log do
      with_snapshot(Snapshot.new(backlog: 100, oldest_ready_age_seconds: 600, failed: 0)) do
        ReportQueueHealthJob.new.perform
      end
    end
    assert_match(/ERROR.*oldest_ready_age_s=600/, log)
  end

  private

  # Replace QueueHealth.snapshot for the duration of the block. Avoids the
  # Minitest::Mock require dance — the gem version pinned by this project
  # doesn't expose `Object#stub` without it.
  def with_snapshot(snapshot)
    original = QueueHealth.method(:snapshot)
    QueueHealth.define_singleton_method(:snapshot) { |**_| snapshot }
    yield
  ensure
    QueueHealth.define_singleton_method(:snapshot, &original)
  end

  def capture_log
    io = StringIO.new
    original = Rails.logger
    logger = ActiveSupport::Logger.new(io)
    logger.level = Logger::DEBUG
    logger.formatter = ->(severity, _time, _progname, msg) { "#{severity} #{msg}\n" }
    Rails.logger = logger
    yield
    io.string
  ensure
    Rails.logger = original
  end
end

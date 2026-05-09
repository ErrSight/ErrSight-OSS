require "test_helper"
require "rake"

class TimescaleRakeTest < ActiveSupport::TestCase
  include StubHelper

  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("timescale:stats")
    @task = Rake::Task["timescale:stats"]
    @task.reenable
    TimescaleStats.clear_cache
  end

  test "timescale:stats prints hypertable summary when extension is available" do
    out, = capture_io { @task.invoke }

    assert_match(/events hypertable/, out)
    assert_match(/Total chunks\s*:/, out)
    assert_match(/Compressed chunks\s*:/, out)
    assert_match(/Uncompressed \(hot\)\s*:/, out)
    assert_match(/Size on disk\s*:/, out)
    assert_match(/Storage saved\s*:/, out)
    assert_match(/Compression ratio\s*:/, out)
    assert_match(/Per-chunk breakdown/, out)
  end

  test "timescale:stats exits with status 1 when extension is unavailable" do
    stub_method(TimescaleStats, :hypertable, { available: false }) do
      out, = capture_io do
        err = assert_raises(SystemExit) { @task.invoke }
        assert_equal 1, err.status
      end
      assert_match(/not available/i, out)
    end
  end

  test "timescale:stats uses raw bytes passed through number_to_human_size" do
    fake_stats = {
      available: true,
      total_chunks: 3,
      compressed_chunks: 1,
      uncompressed_chunks: 2,
      before_bytes: 2048,
      after_bytes: 512,
      bytes_saved: 1536,
      ratio: 4.0,
      uncompressed_bytes: 1024,
      total_bytes_on_disk: 1536
    }

    stub_method(TimescaleStats, :hypertable, fake_stats) do
      out, = capture_io { @task.invoke }
      assert_match(/Total chunks\s*:\s*3/, out)
      assert_match(/Compressed chunks\s*:\s*1/, out)
      assert_match(/Uncompressed \(hot\)\s*:\s*2/, out)
      assert_match(/Compression ratio\s*:\s*4\.0x/, out)
    end
  end
end

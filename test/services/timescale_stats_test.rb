require "test_helper"

class TimescaleStatsTest < ActiveSupport::TestCase
  include StubHelper

  setup do
    TimescaleStats.clear_cache
    @project = projects(:alpha)
    @event   = events(:error_event)
  end

  # ── installed? ───────────────────────────────────────────────────────────────

  test "installed? returns true when the timescaledb extension is present" do
    assert_equal true, TimescaleStats.installed?
  end

  test "installed? returns false when the extension query raises StatementInvalid" do
    TimescaleStats.clear_cache
    conn = ActiveRecord::Base.connection
    stub_method(conn, :select_value, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
      assert_equal false, TimescaleStats.installed?
    end
  ensure
    TimescaleStats.clear_cache
  end

  # ── hypertable ───────────────────────────────────────────────────────────────

  test "hypertable returns available stats with the expected keys when installed" do
    stats = TimescaleStats.hypertable

    assert stats[:available]
    expected_keys = %i[
      available total_chunks compressed_chunks uncompressed_chunks
      before_bytes after_bytes bytes_saved ratio
      uncompressed_bytes total_bytes_on_disk
    ]
    assert_equal expected_keys.sort, stats.keys.sort
  end

  test "hypertable reports non-negative chunk counts and sizes" do
    stats = TimescaleStats.hypertable

    assert stats[:total_chunks] >= 0
    assert stats[:compressed_chunks] >= 0
    assert stats[:uncompressed_chunks] >= 0
    assert_equal stats[:total_chunks],
                 stats[:compressed_chunks] + stats[:uncompressed_chunks]
    assert stats[:before_bytes] >= 0
    assert stats[:after_bytes]  >= 0
    assert stats[:bytes_saved]  >= 0
    assert stats[:uncompressed_bytes]   >= 0
    assert stats[:total_bytes_on_disk]  >= 0
  end

  test "hypertable returns unavailable when extension is not installed" do
    stub_method(TimescaleStats, :installed?, false) do
      assert_equal({ available: false }, TimescaleStats.hypertable)
    end
  end

  test "hypertable swallows StatementInvalid and returns unavailable" do
    stub_method(TimescaleStats, :installed?, true) do
      conn = ActiveRecord::Base.connection
      stub_method(conn, :select_one, ->(*) { raise ActiveRecord::StatementInvalid, "bad sql" }) do
        assert_equal({ available: false }, TimescaleStats.hypertable)
      end
    end
  end

  test "hypertable computes compression ratio when after_bytes is positive" do
    stub_method(TimescaleStats, :installed?, true) do
      fake_row = {
        "total_chunks" => 4,
        "compressed_chunks" => 2,
        "before_compression_total_bytes" => 1000,
        "after_compression_total_bytes"  => 250
      }
      conn = ActiveRecord::Base.connection
      stub_method(conn, :select_one, fake_row) do
        stub_method(conn, :select_value, 500) do
          stats = TimescaleStats.hypertable
          assert_equal 4, stats[:total_chunks]
          assert_equal 2, stats[:compressed_chunks]
          assert_equal 2, stats[:uncompressed_chunks]
          assert_equal 1000, stats[:before_bytes]
          assert_equal 250,  stats[:after_bytes]
          assert_equal 750,  stats[:bytes_saved]
          assert_equal 4.0,  stats[:ratio]
          assert_equal 500,  stats[:uncompressed_bytes]
          assert_equal 750,  stats[:total_bytes_on_disk] # 250 + 500
        end
      end
    end
  end

  test "hypertable returns nil ratio when after_bytes is zero" do
    stats = TimescaleStats.hypertable
    if stats[:after_bytes].zero?
      assert_nil stats[:ratio]
    end
  end

  # ── chunk_for / compressed? ──────────────────────────────────────────────────

  test "chunk_for returns nil when extension is not installed" do
    stub_method(TimescaleStats, :installed?, false) do
      assert_nil TimescaleStats.chunk_for(@event)
    end
  end

  test "chunk_for returns nil when event.occurred_at is blank" do
    blank_event = Event.new(id: 999999, occurred_at: nil)
    assert_nil TimescaleStats.chunk_for(blank_event)
  end

  test "chunk_for returns a chunk hash for a persisted event" do
    chunk = TimescaleStats.chunk_for(@event)
    assert chunk.is_a?(Hash)
    assert chunk[:chunk_name].present?
    assert chunk[:chunk_schema].present?
    assert_equal "#{chunk[:chunk_schema]}.#{chunk[:chunk_name]}", chunk[:full_name]
    assert chunk[:range_start] <= @event.occurred_at
    assert chunk[:range_end]   >  @event.occurred_at
    assert_includes [ true, false ], chunk[:is_compressed]
  end

  test "chunk_for returns nil on StatementInvalid" do
    stub_method(TimescaleStats, :installed?, true) do
      conn = ActiveRecord::Base.connection
      stub_method(conn, :select_one, ->(*) { raise ActiveRecord::StatementInvalid, "bad sql" }) do
        assert_nil TimescaleStats.chunk_for(@event)
      end
    end
  end

  test "compressed? is false for an uncompressed chunk" do
    # In the test DB freshly migrated chunks are not yet compressed
    # (compression policy runs on 7-day-old data).
    assert_equal false, TimescaleStats.compressed?(@event)
  end

  test "compressed? is true when the chunk lookup reports compression" do
    stub_method(TimescaleStats, :chunk_for, { is_compressed: true }) do
      assert_equal true, TimescaleStats.compressed?(@event)
    end
  end

  test "compressed? is false when chunk_for returns nil" do
    stub_method(TimescaleStats, :chunk_for, nil) do
      assert_equal false, TimescaleStats.compressed?(@event)
    end
  end

  # ── clear_cache ──────────────────────────────────────────────────────────────

  test "clear_cache does not raise when cache supports delete_matched" do
    assert_nothing_raised { TimescaleStats.clear_cache }
  end

  test "clear_cache is a no-op when cache does not support delete_matched" do
    bare_cache = Object.new
    stub_method(Rails, :cache, bare_cache) do
      assert_nothing_raised { TimescaleStats.clear_cache }
    end
  end

  # ── HYPERTABLE constant ──────────────────────────────────────────────────────

  test "HYPERTABLE constant points at the events table" do
    assert_equal "events", TimescaleStats::HYPERTABLE
  end
end

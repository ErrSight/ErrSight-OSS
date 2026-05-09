require "test_helper"

class TimescaleHypertableTest < ActiveSupport::TestCase
  include StubHelper

  # ── no-op paths ──────────────────────────────────────────────────────────────

  test "ensure! reports :extension_unavailable and runs no DDL on plain Postgres" do
    stub_method(TimescaleHypertable, :installed?, false) do
      stub_method(TimescaleHypertable, :available?, false) do
        executed = capture_execute do
          assert_equal :extension_unavailable, TimescaleHypertable.ensure!
        end
        assert_empty executed, "no DDL should run when timescaledb is unavailable"
      end
    end
  end

  test "ensure! reports :already_configured and runs no DDL when fully set up" do
    with_state(installed: true, hypertable: true, licensed: true,
               compression: true, policy: true) do
      executed = capture_execute do
        assert_equal :already_configured, TimescaleHypertable.ensure!
      end
      assert_empty executed, "an already-configured DB needs no DDL"
    end
  end

  # ── conversion paths ─────────────────────────────────────────────────────────

  test "ensure! creates the hypertable, compression, and policy when missing" do
    with_state(installed: true, hypertable: false, licensed: true,
               compression: false, policy: false) do
      executed = capture_execute do
        assert_equal :configured, TimescaleHypertable.ensure!
      end
      joined = executed.join("\n")
      assert_match(/create_hypertable\('events', 'occurred_at'/, joined)
      assert_match(/migrate_data\s+=> TRUE/, joined)
      assert_match(/timescaledb\.compress_segmentby = 'project_id'/, joined)
      assert_match(/add_compression_policy\('events', INTERVAL '7 days'\)/, joined)
    end
  end

  test "ensure! creates the hypertable but skips compression on an Apache build" do
    with_state(installed: true, hypertable: false, licensed: false,
               compression: false, policy: false) do
      executed = capture_execute do
        assert_equal :configured, TimescaleHypertable.ensure!
      end
      joined = executed.join("\n")
      assert_match(/create_hypertable/, joined)
      refute_match(/timescaledb\.compress/, joined)
      refute_match(/add_compression_policy/, joined)
    end
  end

  test "ensure! skips the compression ALTER once compression is already configured" do
    with_state(installed: true, hypertable: true, licensed: true,
               compression: true, policy: false) do
      executed = capture_execute do
        assert_equal :configured, TimescaleHypertable.ensure!
      end
      joined = executed.join("\n")
      refute_match(/ALTER TABLE events SET/, joined, "must not re-ALTER compressed chunks")
      assert_match(/add_compression_policy/, joined)
    end
  end

  # ── resilience ───────────────────────────────────────────────────────────────

  test "ensure! swallows errors and reports :error, never raising" do
    stub_method(TimescaleHypertable, :installed?, true) do
      stub_method(TimescaleHypertable, :hypertable?, false) do
        conn = ActiveRecord::Base.connection
        stub_method(conn, :execute, ->(*) { raise ActiveRecord::StatementInvalid, "boom" }) do
          assert_nothing_raised do
            assert_equal :error, TimescaleHypertable.ensure!
          end
        end
      end
    end
  end

  # ── constants ────────────────────────────────────────────────────────────────

  test "HYPERTABLE constant points at the events table" do
    assert_equal "events", TimescaleHypertable::HYPERTABLE
  end

  private

  # Runs the block with connection.execute stubbed to record (not run) every
  # statement, and returns the recorded SQL strings.
  def capture_execute
    executed = []
    conn = ActiveRecord::Base.connection
    stub_method(conn, :execute, ->(sql, *) { executed << sql.to_s }) do
      yield
    end
    executed
  end

  # Stubs every state predicate so ensure! exercises a chosen branch without
  # touching the real database.
  def with_state(installed:, hypertable:, licensed:, compression:, policy:)
    stub_method(TimescaleHypertable, :installed?, installed) do
      stub_method(TimescaleHypertable, :available?, installed) do
        stub_method(TimescaleHypertable, :hypertable?, hypertable) do
          stub_method(TimescaleHypertable, :tsl_licensed?, licensed) do
            stub_method(TimescaleHypertable, :compression_configured?, compression) do
              stub_method(TimescaleHypertable, :compression_policy?, policy) do
                yield
              end
            end
          end
        end
      end
    end
  end
end

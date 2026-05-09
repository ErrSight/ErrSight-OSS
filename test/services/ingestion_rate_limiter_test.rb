require "test_helper"

class IngestionRateLimiterTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
    @project.update!(rate_limit_per_minute: 10)
  end

  test "allows requests under the per-minute limit" do
    result = IngestionRateLimiter.check!(@project, count: 5)
    assert result.allowed
    assert_equal 10, result.limit
    assert_equal 5, result.count
    assert_equal 5, result.remaining
    assert_equal 0, result.retry_after
  end

  test "accumulates usage within the same window" do
    IngestionRateLimiter.check!(@project, count: 4)
    result = IngestionRateLimiter.check!(@project, count: 3)
    assert result.allowed
    assert_equal 7, result.count
    assert_equal 3, result.remaining
  end

  test "rejects when the batch would exceed the limit" do
    IngestionRateLimiter.check!(@project, count: 8)
    result = IngestionRateLimiter.check!(@project, count: 5)
    refute result.allowed
    assert_equal 8, result.count
    assert_equal 2, result.remaining
    assert result.retry_after >= 1
    assert result.retry_after <= IngestionRateLimiter::WINDOW
  end

  test "rejected requests do not consume tokens" do
    IngestionRateLimiter.check!(@project, count: 8)
    IngestionRateLimiter.check!(@project, count: 5) # rejected, should not advance counter
    result = IngestionRateLimiter.check!(@project, count: 2)
    assert result.allowed
    assert_equal 10, result.count
  end

  test "returns allowed with infinite remaining when limit is zero or negative" do
    @project.update!(rate_limit_per_minute: 0)
    result = IngestionRateLimiter.check!(@project, count: 10_000)
    assert result.allowed
    assert_equal Float::INFINITY, result.remaining
    assert_equal 0, result.retry_after
  end

  test "resets counts when the window rolls over" do
    now = Time.zone.local(2026, 4, 20, 12, 0, 30)
    IngestionRateLimiter.check!(@project, count: 10, now: now)
    over = IngestionRateLimiter.check!(@project, count: 1, now: now)
    refute over.allowed

    next_window = now + IngestionRateLimiter::WINDOW
    fresh = IngestionRateLimiter.check!(@project, count: 10, now: next_window)
    assert fresh.allowed
    assert_equal 10, fresh.count
  end

  test "reset! clears all window state" do
    IngestionRateLimiter.check!(@project, count: 10)
    IngestionRateLimiter.reset!
    result = IngestionRateLimiter.check!(@project, count: 10)
    assert result.allowed
    assert_equal 10, result.count
  end

  test "projects are isolated from each other" do
    other = projects(:admin_project)
    other.update!(rate_limit_per_minute: 10)
    IngestionRateLimiter.check!(@project, count: 10)
    result = IngestionRateLimiter.check!(other, count: 10)
    assert result.allowed
  end
end

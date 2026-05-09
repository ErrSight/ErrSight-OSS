require "test_helper"

class ProjectTest < ActiveSupport::TestCase
  setup do
    @org  = organizations(:regular_org)
    @user = users(:regular)
  end

  def build(**overrides)
    Project.new({ name: "Sample", user: @user, organization: @org }.merge(overrides))
  end

  test "valid with required attributes" do
    assert build.valid?
  end

  test "invalid without name" do
    assert_not build(name: nil).valid?
  end

  test "rate_limit_per_minute is required" do
    assert_not build(rate_limit_per_minute: nil).valid?
  end

  test "rate_limit_per_minute rejects negatives" do
    assert_not build(rate_limit_per_minute: -1).valid?
  end

  test "rate_limit_per_minute accepts 0 (disables limiting)" do
    assert build(rate_limit_per_minute: 0).valid?
  end

  test "auto-generates api_key on create" do
    p = build
    p.save!
    assert p.api_key.start_with?("elp_")
    assert_equal 4 + 48, p.api_key.length
  end

  test "auto-generates slug from name on create" do
    p = build(name: "My App")
    p.save!
    assert_equal "my-app", p.slug
  end

  test "slug-collision counter" do
    build(name: "App").save!
    second = build(name: "App")
    second.save!
    assert_equal "app-1", second.slug
  end

  test "ensure_default_api_key creates an ApiKey row" do
    p = build
    p.save!
    assert_equal 1, p.api_keys.count
    assert_equal p.api_key, p.api_keys.first.token
  end

  test "drop_reason is nil by default" do
    p = build
    p.save!
    assert_nil p.drop_reason
  end

  test "drop_reason is 'ingestion_paused' when paused" do
    p = build
    p.save!
    p.update!(ingestion_paused: true)
    assert_equal "ingestion_paused", p.drop_reason
  end

  test "rotate_default_api_key! generates a new token" do
    p = build
    p.save!
    old_token = p.api_key
    p.rotate_default_api_key!
    p.reload
    assert_not_equal old_token, p.api_key
    assert p.api_key.start_with?("elp_")
  end

  test "to_param returns the id" do
    p = build
    p.save!
    assert_equal p.id.to_s, p.to_param
  end
end

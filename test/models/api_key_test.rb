require "test_helper"

class ApiKeyTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "write scope gets elp_ prefix" do
    key = @project.api_keys.create!(name: "Write", scope: :write)
    assert_match(/\Aelp_[0-9a-f]{48}\z/, key.token)
  end

  test "read scope gets elr_ prefix" do
    key = @project.api_keys.create!(name: "Read", scope: :read)
    assert_match(/\Aelr_[0-9a-f]{48}\z/, key.token)
  end

  test "token must be unique across projects" do
    first = @project.api_keys.create!(name: "A", scope: :read)
    other = projects(:beta).api_keys.new(name: "B", scope: :read, token: first.token)
    assert_not other.valid?
  end

  test "name is required" do
    key = @project.api_keys.new(scope: :read, name: "")
    assert_not key.valid?
  end

  test "revoke! sets revoked_at" do
    key = @project.api_keys.create!(name: "X", scope: :read)
    key.revoke!
    assert_not_nil key.revoked_at
    assert_predicate key, :revoked?
  end

  test "find_active_by_token ignores revoked keys" do
    key = @project.api_keys.create!(name: "X", scope: :read)
    key.revoke!
    assert_nil ApiKey.find_active_by_token(key.token)
  end

  test "project auto-creates default write key on create" do
    org = organizations(:regular_org)
    project = org.projects.create!(name: "Fresh", user: users(:regular))
    key = project.api_keys.first
    assert_equal 1, project.api_keys.count
    assert_equal "write", key.scope
    assert_equal project.api_key, key.token
  end

  test "rotate_default_api_key! updates project token and the default key" do
    old_token = @project.api_key
    default   = @project.api_keys.find_by(token: old_token)
    assert_not_nil default
    @project.rotate_default_api_key!
    @project.reload
    default.reload
    assert_not_equal old_token, @project.api_key
    assert_equal @project.api_key, default.token
  end
end

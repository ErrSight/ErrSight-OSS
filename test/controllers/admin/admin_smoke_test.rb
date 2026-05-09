require "test_helper"

# Smoke test that every ActiveAdmin index renders without error for an admin
# user. ActiveAdmin resource files are mostly DSL declarations — they rarely
# break in isolation but a missing column reference, a removed model attribute,
# or a typo in a `column` block crashes the page at request time. This test
# catches those at CI time instead of via the admin user clicking around.
class AdminSmokeTest < ActionDispatch::IntegrationTest
  setup { sign_in users(:admin) }

  ADMIN_INDEX_PATHS = %w[
    /admin
    /admin/dashboard
    /admin/users
    /admin/organizations
    /admin/projects
    /admin/events
    /admin/plans
    /admin/invitations
    /admin/memberships
  ].freeze

  ADMIN_INDEX_PATHS.each do |path|
    test "GET #{path} loads for an admin user" do
      get path
      assert_response :success, "expected #{path} to render; got #{response.status}"
    end
  end

  test "admin index pages redirect non-admin users" do
    sign_out users(:admin)
    sign_in users(:regular)

    get "/admin/users"
    assert_response :redirect, "non-admin users must not access /admin"
  end
end

require "test_helper"

# Pins the admin guard on the mission_control-jobs UI mounted at /jobs.
# The dashboard exposes raw job arguments — including ProcessEventJob
# payloads with user PII — so this guard is a privacy boundary, not just
# an admin convenience. If anyone removes the
# `authenticated :user, ->(u) { u.admin? }` block in routes.rb this test
# fails loudly. Devise's `authenticated` block is a route constraint:
# non-matching requests get 404 (not a sign-in redirect), which is the
# right behavior — it doesn't even acknowledge the route exists.
class JobsDashboardTest < ActionDispatch::IntegrationTest
  test "non-authenticated requests to /jobs return 404" do
    get "/jobs"
    assert_response :not_found
  end

  test "non-admin authenticated users cannot reach /jobs" do
    sign_in users(:regular)
    get "/jobs"
    assert_response :not_found
  end

  # Verifies the admin gets *past* the Devise route guard and Mission
  # Control's basic-auth layer. We can't assert a fully-rendered dashboard:
  # ActiveJob in test uses :test adapter, and Mission Control wires up its
  # adapter extensions at engine boot time keyed on whatever adapter was
  # configured then — swapping at request time is too late, so the dashboard
  # raises NoMethodError on the TestAdapter when it tries to introspect.
  # Reaching that error proves the request flowed through to the engine,
  # which is the only thing this test cares about.
  test "admin users get past the route guard at /jobs" do
    sign_in users(:admin)
    begin
      get "/jobs"
    rescue NoMethodError => e
      assert_match(/activating|TestAdapter|SolidQueue/, e.message,
        "admin reached Mission Control, but the error wasn't the expected adapter mismatch")
      return
    end
    # If the gem ever stops blowing up under TestAdapter (or someone configures
    # solid_queue for test), a real success/redirect is also acceptable.
    refute_equal 404, response.status, "admin should not see 404 at /jobs"
    refute_equal 401, response.status, "admin should not be challenged for basic auth"
  end
end

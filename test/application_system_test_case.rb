require "test_helper"

# The auth forms submit through Turbo, so a failed sign-in is an async
# POST → 422 → re-render round trip. On a loaded CI runner that can exceed
# Capybara's stock 2s wait before the flash renders, intermittently failing
# assertions like "Invalid email or password." A wider margin removes the race
# without slowing passing assertions (they return as soon as the text appears).
Capybara.default_max_wait_time = 5

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  include Warden::Test::Helpers

  teardown { Warden.test_reset! }

  def sign_in_as(user)
    login_as(user, scope: :user)
  end
end

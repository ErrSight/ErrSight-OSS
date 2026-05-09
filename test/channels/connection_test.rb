require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "rejects unauthorized connection when no Warden user is present" do
    assert_reject_connection { connect }
  end

  test "rejects unauthorized connection when Warden has nil user" do
    assert_reject_connection { connect env: { "warden" => FakeWarden.new(nil) } }
  end

  test "accepts connection and exposes current_user when Warden has a user" do
    user = users(:regular)
    connect env: { "warden" => FakeWarden.new(user) }
    assert_equal user, connection.current_user
  end

  # Stand-in for Warden — the real Warden::Proxy needs a full Rack env.
  # ApplicationCable::Connection only calls `.user` on it, so this is enough.
  class FakeWarden
    def initialize(user) = @user = user
    def user = @user
  end
end

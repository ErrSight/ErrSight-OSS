require "test_helper"

class WebhookEndpointTest < ActiveSupport::TestCase
  setup do
    @project = projects(:alpha)
  end

  test "auto-generates a secret with the whk_ prefix" do
    endpoint = @project.webhook_endpoints.create!(url: "https://example.com/hook")
    assert_match(/\Awhk_[a-f0-9]{64}\z/, endpoint.secret)
  end

  test "rejects non-http(s) URLs" do
    endpoint = @project.webhook_endpoints.build(url: "ftp://example.com")
    assert_not endpoint.valid?
    assert_includes endpoint.errors[:url].join, "http"
  end

  test "active scope excludes disabled endpoints" do
    active = @project.webhook_endpoints.create!(url: "https://a.com/x")
    disabled = @project.webhook_endpoints.create!(url: "https://b.com/x", active: false)
    actives = @project.webhook_endpoints.active
    assert_includes actives, active
    assert_not_includes actives, disabled
  end
end

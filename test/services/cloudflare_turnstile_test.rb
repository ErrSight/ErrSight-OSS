require "test_helper"

class CloudflareTurnstileTest < ActiveSupport::TestCase
  include StubHelper

  test "enabled? is false when site key is missing" do
    with_env("CLOUDFLARE_TURNSTILE_SITE_KEY" => nil, "CLOUDFLARE_TURNSTILE_SECRET_KEY" => "secret") do
      assert_not CloudflareTurnstile.enabled?
    end
  end

  test "enabled? is false when secret key is missing" do
    with_env("CLOUDFLARE_TURNSTILE_SITE_KEY" => "site", "CLOUDFLARE_TURNSTILE_SECRET_KEY" => nil) do
      assert_not CloudflareTurnstile.enabled?
    end
  end

  test "verify returns true when disabled (no keys configured)" do
    with_env("CLOUDFLARE_TURNSTILE_SITE_KEY" => nil, "CLOUDFLARE_TURNSTILE_SECRET_KEY" => nil) do
      assert CloudflareTurnstile.verify("anything")
    end
  end

  test "verify returns false when enabled but token is blank" do
    with_env("CLOUDFLARE_TURNSTILE_SITE_KEY" => "site", "CLOUDFLARE_TURNSTILE_SECRET_KEY" => "secret") do
      assert_not CloudflareTurnstile.verify(nil)
      assert_not CloudflareTurnstile.verify("")
    end
  end

  test "verify returns false and logs on network error" do
    with_env("CLOUDFLARE_TURNSTILE_SITE_KEY" => "site", "CLOUDFLARE_TURNSTILE_SECRET_KEY" => "secret") do
      stub_method(Net::HTTP, :post_form, ->(*) { raise SocketError, "boom" }) do
        assert_not CloudflareTurnstile.verify("token")
      end
    end
  end

  private

  def with_env(values)
    old = values.transform_values { |_| :__missing__ }
    values.each_key { |k| old[k] = ENV.key?(k) ? ENV[k] : :__missing__ }
    values.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    yield
  ensure
    old.each do |k, v|
      v == :__missing__ ? ENV.delete(k) : ENV[k] = v
    end
  end
end

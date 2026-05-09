# frozen_string_literal: true

require "net/http"
require "uri"

# Verifies Cloudflare Turnstile tokens server-side.
#
# Disabled (no-op, returns true) when either env var is blank, so local
# dev and the test suite work without configuring keys. Set both
# CLOUDFLARE_TURNSTILE_SITE_KEY and CLOUDFLARE_TURNSTILE_SECRET_KEY in
# production to turn the gate on.
module CloudflareTurnstile
  SITEVERIFY_URL = URI("https://challenges.cloudflare.com/turnstile/v0/siteverify")

  module_function

  def site_key
    ENV["CLOUDFLARE_TURNSTILE_SITE_KEY"].presence
  end

  def secret_key
    ENV["CLOUDFLARE_TURNSTILE_SECRET_KEY"].presence
  end

  def enabled?
    site_key.present? && secret_key.present?
  end

  def verify(token, remote_ip: nil)
    return true unless enabled?
    return false if token.blank?

    response = Net::HTTP.post_form(SITEVERIFY_URL,
      "secret"   => secret_key,
      "response" => token,
      "remoteip" => remote_ip.to_s
    )
    return false unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).fetch("success", false) == true
  rescue StandardError => e
    Rails.logger.warn "[Turnstile] verification error: #{e.class}: #{e.message}"
    false
  end
end

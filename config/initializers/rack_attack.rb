class Rack::Attack
  # Allow localhost only in development — in production deployments behind a
  # reverse proxy on the same host, req.ip is the proxy's loopback address,
  # which would silently exempt all public traffic from throttles.
  if Rails.env.development?
    safelist("allow-localhost") do |req|
      req.ip == "127.0.0.1" || req.ip == "::1"
    end
  end

  # API event ingestion is not throttled here — it's rate-limited per project
  # at the application layer in Api::V1::EventsController, via
  # IngestionRateLimiter plus a per-project ingestion-paused gate.

  # Throttle login attempts: 5 per 20 seconds per IP
  throttle("login/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Throttle sign-up: 3 per hour per IP
  throttle("signup/ip", limit: 3, period: 1.hour) do |req|
    req.ip if req.path == "/users" && req.post?
  end

  # Throttle password-reset requests: 5 per hour per IP. Devise's
  # POST /users/password sends a reset email on every call; unthrottled it lets
  # an attacker flood a victim's inbox.
  throttle("password_reset/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end

  # Throttle confirmation-instructions resend: 5 per hour per IP. Same
  # email-flood risk as password reset.
  throttle("confirmation/ip", limit: 5, period: 1.hour) do |req|
    req.ip if req.path == "/users/confirmation" && req.post?
  end

  # Throttle invitation resends: 10 per hour per IP. The action is already behind
  # admin auth, but without a cap an admin (or a hijacked admin session) can loop
  # it to spam an invitee.
  throttle("invitation_resend/ip", limit: 10, period: 1.hour) do |req|
    req.ip if req.post? && req.path.match?(%r{\A/organizations/\d+/invitations/\d+/resend\z})
  end

  # Block suspicious user agents
  blocklist("block-bad-actors") do |req|
    # Add known malicious agents here if needed
    false
  end

  # Custom response for throttled requests
  self.throttled_responder = lambda do |req|
    match_data = req.env["rack.attack.match_data"]
    [
      429,
      { "Content-Type" => "application/json" },
      [ { error: "Rate limit exceeded. Please slow down.", retry_after: match_data[:period] }.to_json ]
    ]
  end
end

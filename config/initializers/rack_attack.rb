class Rack::Attack
  # Allow localhost only in development — in production deployments behind a
  # reverse proxy on the same host, req.ip is the proxy's loopback address,
  # which would silently exempt all public traffic from throttles.
  if Rails.env.development?
    safelist("allow-localhost") do |req|
      req.ip == "127.0.0.1" || req.ip == "::1"
    end
  end

  # API event ingestion is not throttled here — plan-based monthly quotas
  # and storage limits are enforced at the application layer in
  # Api::V1::EventsController (reserve_event_quota!, check_ingestion_limits).

  # Throttle login attempts: 5 per 20 seconds per IP
  throttle("login/ip", limit: 5, period: 20.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  # Throttle sign-up: 3 per hour per IP
  throttle("signup/ip", limit: 3, period: 1.hour) do |req|
    req.ip if req.path == "/users" && req.post?
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

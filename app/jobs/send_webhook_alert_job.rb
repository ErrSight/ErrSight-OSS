require "net/http"
require "openssl"
require "resolv"
require "ipaddr"

class SendWebhookAlertJob < ApplicationJob
  queue_as :alerts

  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5
  MAX_FAILURES_BEFORE_DISABLE = 10

  # Mirror of WebhookEndpoint::PRIVATE_IP_RANGES — rechecked at send time so
  # DNS-rebinding can't slip a private IP past validation.
  PRIVATE_IP_RANGES = WebhookEndpoint::PRIVATE_IP_RANGES

  class PrivateAddressError < StandardError; end

  retry_on Net::OpenTimeout, Net::ReadTimeout, wait: 30.seconds, attempts: 3
  discard_on ActiveJob::DeserializationError

  def perform(event_id)
    event = EventRepository.find(event_id)
    return unless event

    project = event.project
    return unless alert_rule_matches?(project, event)

    endpoints = project.webhook_endpoints.active.to_a
    return if endpoints.empty?

    payload = build_payload(event, project)
    body    = payload.to_json

    endpoints.each { |endpoint| deliver(endpoint, body) }
  end

  private

  def alert_rule_matches?(project, event)
    rules = project.alert_rules.active.to_a
    return true if rules.empty?
    rules.any? { |rule| rule.matches?(event) }
  end

  def build_payload(event, project)
    {
      id:             event.id,
      event:          event.is_regression? ? "issue.regressed" : "issue.created",
      delivered_at:   Time.current.iso8601,
      project: {
        id:   project.id,
        name: project.name,
        slug: project.slug
      },
      data: {
        id:              event.id,
        level:           event.level,
        message:         event.message,
        environment:     event.environment,
        fingerprint:     event.fingerprint,
        release:         event.release,
        is_regression:   event.is_regression,
        occurred_at:     event.occurred_at&.iso8601,
        user_identifier: event.user_identifier,
        user_context:    event.user_context,
        tags:            event.tags,
        url:             event_url(project, event)
      }
    }
  end

  def deliver(endpoint, body)
    log_host = endpoint_host(endpoint)
    uri  = URI.parse(endpoint.url)
    host = uri.host.to_s

    # Resolve at send-time and dial the IP directly to defeat DNS rebinding.
    # Net::HTTP#ipaddr= sets the underlying socket target without changing the
    # TLS SNI or the Host header, which stay keyed on the hostname.
    ip = safe_resolve_ip(host)
    raise PrivateAddressError, "refused: #{host} resolved to private/reserved IP" unless ip

    http = Net::HTTP.new(host, uri.port)
    http.ipaddr = ip
    http.use_ssl = (uri.scheme == "https")
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

    timestamp = Time.current.to_i.to_s
    signature = sign(endpoint.secret, timestamp, body)

    request = Net::HTTP::Post.new(uri.request_uri)
    request["Content-Type"]          = "application/json"
    request["User-Agent"]            = "ErrSight-Webhook/1.0"
    request["X-ErrSight-Timestamp"]  = timestamp
    request["X-ErrSight-Signature"]  = "sha256=#{signature}"
    request.body = body

    response = http.request(request)
    if response.is_a?(Net::HTTPSuccess)
      endpoint.update_columns(last_delivered_at: Time.current, failure_count: 0)
    else
      Rails.logger.warn("[SendWebhookAlertJob] delivery failed endpoint=#{endpoint.id} host=#{log_host} status=#{response.code}")
      record_failure(endpoint, "HTTP #{response.code}")
    end
  rescue PrivateAddressError
    Rails.logger.warn("[SendWebhookAlertJob] delivery refused endpoint=#{endpoint.id} host=#{log_host} reason=private_address")
    record_failure(endpoint, "private_address")
  rescue StandardError => e
    Rails.logger.warn("[SendWebhookAlertJob] delivery failed endpoint=#{endpoint.id} host=#{log_host} error=#{e.class}")
    record_failure(endpoint, e.class.to_s)
  end

  # Returns a public IP string for the host, or nil if resolution fails or
  # every resolved address is private/reserved.
  def safe_resolve_ip(host)
    return nil if host.blank?

    # Literal-IP URLs skip DNS; check directly.
    begin
      literal = IPAddr.new(host)
      return nil if private_address?(literal)
      return literal.to_s
    rescue IPAddr::Error
      # Not a literal IP — fall through to DNS.
    end

    addresses = Resolv.getaddresses(host)
    addresses.each do |addr|
      ip = IPAddr.new(addr)
      next if private_address?(ip)
      return ip.to_s
    end
    nil
  rescue Resolv::ResolvError, IPAddr::Error
    nil
  end

  # Normalize IPv4-mapped IPv6 (e.g. ::ffff:127.0.0.1) to native IPv4 before
  # range-matching, so an attacker can't hop the IPv4 private checks by
  # resolving/providing the mapped form.
  def private_address?(ip)
    native = ip.ipv4_mapped? ? ip.native : ip
    PRIVATE_IP_RANGES.any? { |range| range.include?(native) }
  end

  def record_failure(endpoint, reason)
    # Atomic increment at the DB level. increment! reads the in-memory value
    # and writes value+1, so two concurrent retries can both read N and both
    # write N+1, losing an increment and letting a flaky endpoint dodge the
    # disable threshold.
    WebhookEndpoint.where(id: endpoint.id).update_all("failure_count = failure_count + 1, updated_at = NOW()")
    endpoint.reload
    if endpoint.failure_count >= MAX_FAILURES_BEFORE_DISABLE
      endpoint.update_columns(active: false)
      Rails.logger.warn("[SendWebhookAlertJob] disabled endpoint #{endpoint.id} after #{endpoint.failure_count} failures (#{reason})")
    end
  end

  def endpoint_host(endpoint)
    URI.parse(endpoint.url).host.to_s.presence || "invalid"
  rescue URI::InvalidURIError
    "invalid"
  end

  def sign(secret, timestamp, body)
    OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")
  end

  def event_url(project, event)
    opts = Rails.application.config.action_mailer.default_url_options || {}
    return nil if opts[:host].blank?
    Rails.application.routes.url_helpers.project_event_url(project, event, **opts)
  rescue StandardError
    nil
  end
end

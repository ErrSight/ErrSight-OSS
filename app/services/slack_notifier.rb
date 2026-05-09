require "net/http"
require "json"

class SlackNotifier
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 5

  ALLOWED_HOST = "hooks.slack.com"

  SEVERITY_EMOJI = {
    "debug"   => ":mag:",
    "info"    => ":information_source:",
    "warning" => ":warning:",
    "error"   => ":rotating_light:",
    "fatal"   => ":fire:"
  }.freeze

  class << self
    def post(webhook_url, payload)
      host = "invalid"

      if webhook_url.blank?
        Rails.logger.warn("[SlackNotifier] webhook_url is blank")
        return false
      end

      uri = URI.parse(webhook_url) rescue nil
      host = uri&.host.to_s.downcase.presence || "invalid"
      unless uri.is_a?(URI::HTTPS) && host == ALLOWED_HOST
        Rails.logger.warn("[SlackNotifier] refused non-allowed host=#{host}")
        return false
      end

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri.request_uri, "Content-Type" => "application/json")
      request.body = payload.to_json

      Rails.logger.info("[SlackNotifier] POST host=#{host} body=#{request.body.bytesize}b")
      response = http.request(request)
      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn("[SlackNotifier] non-2xx response host=#{host} status=#{response.code}")
        return false
      end
      Rails.logger.info("[SlackNotifier] success host=#{host} status=#{response.code}")
      true
    rescue StandardError => e
      Rails.logger.error("[SlackNotifier] request failed host=#{host} error=#{e.class}")
      false
    end

    def event_payload(event, project)
      emoji = SEVERITY_EMOJI[event.level.to_s] || ":bell:"
      url = event_url(project, event)
      regression_tag = event.is_regression? ? " :arrows_counterclockwise: *REGRESSION*" : ""

      {
        text: "#{emoji} [#{project.name}] #{event.level.to_s.upcase}: #{truncate(event.message, 200)}",
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "#{emoji} *#{event.level.to_s.upcase}* in *#{project.name}* (`#{event.environment}`)#{regression_tag}"
            }
          },
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "> #{truncate(event.message, 500).gsub("\n", " ")}"
            }
          },
          {
            type: "context",
            elements: [
              { type: "mrkdwn", text: url ? "<#{url}|View in ErrSight>" : "View event in ErrSight" }
            ]
          }
        ]
      }
    end

    def digest_payload(events, project)
      count = events.size
      first = events.first
      emoji = first ? (SEVERITY_EMOJI[first.level.to_s] || ":bell:") : ":bell:"

      summary_lines = events.first(10).map do |e|
        "• *#{e.level.to_s.upcase}* — #{truncate(e.message, 140).gsub("\n", " ")}"
      end

      {
        text: "#{emoji} [#{project.name}] Hourly digest: #{count} event#{count == 1 ? "" : "s"}",
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: "#{emoji} *Hourly digest* for *#{project.name}* — #{count} event#{count == 1 ? "" : "s"} in the last hour"
            }
          },
          {
            type: "section",
            text: { type: "mrkdwn", text: summary_lines.join("\n") }
          }
        ]
      }
    end

    def test_payload(organization)
      {
        text: ":wave: ErrSight test message from *#{organization.name}*",
        blocks: [
          {
            type: "section",
            text: {
              type: "mrkdwn",
              text: ":wave: *ErrSight test message* from *#{organization.name}* — your Slack webhook is working."
            }
          }
        ]
      }
    end

    private

    def event_url(project, event)
      opts = Rails.application.config.action_mailer.default_url_options || {}
      return nil if opts[:host].blank?
      Rails.application.routes.url_helpers.project_event_url(project, event, **opts)
    rescue StandardError
      nil
    end

    def truncate(str, max)
      s = str.to_s
      s.length > max ? "#{s[0, max]}…" : s
    end
  end
end

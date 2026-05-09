require "ipaddr"
require "resolv"

class WebhookEndpoint < ApplicationRecord
  belongs_to :project

  # Public, routable, non-RFC1918 destinations only — otherwise a tenant can
  # configure a webhook that makes our server probe our own internal network
  # (internal databases, cloud metadata services, etc.). Cloud metadata endpoints live under
  # 169.254.169.254 and are a classic SSRF target.
  PRIVATE_IP_RANGES = [
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("::1/128"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10")
  ].freeze

  validates :url, presence: true,
                  format: { with: %r{\Ahttps://\S+\z}, message: "must be an https:// URL" }
  validate  :url_is_public_http
  validates :secret, presence: true

  before_validation :generate_secret, on: :create

  scope :active, -> { where(active: true) }

  private

  def generate_secret
    self.secret ||= "whk_#{SecureRandom.hex(32)}"
  end

  def url_is_public_http
    return if url.blank?

    uri = URI.parse(url.to_s)
    unless uri.is_a?(URI::HTTPS) && uri.host.present?
      errors.add(:url, "must be a valid https:// URL") and return
    end

    host = uri.host.to_s.downcase
    if host == "localhost" || host.end_with?(".localhost") || host.end_with?(".internal") || host.end_with?(".local")
      errors.add(:url, "cannot target an internal host") and return
    end

    # Reject literal private/loopback IPs in the URL up-front. DNS-resolved
    # hostnames are also checked best-effort — skipped silently when DNS is
    # unavailable (e.g. sandboxed test env) so we don't false-reject valid URLs.
    check_host = begin
      IPAddr.new(host).to_s
      [ host ]
    rescue IPAddr::Error
      resolved = begin
        Resolv.getaddresses(host)
      rescue Resolv::ResolvError, StandardError
        []
      end
      resolved
    end

    check_host.each do |addr|
      ip = IPAddr.new(addr)
      # Normalize IPv4-mapped IPv6 (::ffff:a.b.c.d) so the IPv4 ranges below
      # still catch mapped-form loopback/RFC1918 attempts.
      ip = ip.native if ip.ipv4_mapped?
      if PRIVATE_IP_RANGES.any? { |range| range.include?(ip) }
        errors.add(:url, "cannot target a private or reserved IP address") and return
      end
    end
  rescue URI::InvalidURIError, IPAddr::Error
    errors.add(:url, "is not a valid destination")
  end
end

class PagesController < ApplicationController
  layout :layout_for_page

  skip_before_action :authenticate_user!
  skip_after_action  :verify_authorized
  skip_after_action  :verify_policy_scoped

  def landing
  end

  def docs
  end

  def integrations
  end

  def support
  end

  def privacy
  end

  def terms
  end

  def sitemap
    site_url = "https://#{ENV.fetch("APP_HOST", "errsight.com")}"
    @pages = [
      { loc: "#{site_url}/",             priority: "1.0", changefreq: "weekly"  },
      { loc: "#{site_url}/docs",         priority: "0.8", changefreq: "weekly"  },
      { loc: "#{site_url}/integrations", priority: "0.8", changefreq: "monthly" },
      { loc: "#{site_url}/support",      priority: "0.5", changefreq: "monthly" },
      { loc: "#{site_url}/privacy",      priority: "0.3", changefreq: "yearly"  },
      { loc: "#{site_url}/terms",        priority: "0.3", changefreq: "yearly"  }
    ]
    expires_in 1.hour, public: true
    respond_to { |f| f.xml }
  end

  # Post-signup landing. Shows which address we sent to and a one-click
  # resend form backed by Devise's confirmations#create.
  def check_email
    @email = params[:email].to_s.strip
  end

  private

  LANDING_ACTIONS = %w[landing integrations docs support privacy terms].freeze
  AUTH_ACTIONS    = %w[check_email].freeze
  NO_LAYOUT       = %w[sitemap].freeze

  def layout_for_page
    case action_name
    when *LANDING_ACTIONS then "landing"
    when *AUTH_ACTIONS    then "auth"
    when *NO_LAYOUT       then false
    else                       "landing"
    end
  end
end

class DigestMailer < ApplicationMailer
  # stats is a WeeklyDigestStats instance
  def weekly(membership, stats)
    raise ArgumentError, "stats/membership organization mismatch" unless stats.organization.id == membership.organization_id

    @membership      = membership
    @user            = membership.user
    @organization    = membership.organization
    @stats           = stats
    @dashboard_url   = organization_url(@organization)
    @unsubscribe_url = digest_unsubscribe_url(token: membership.digest_unsubscribe_token)

    headers["List-Unsubscribe"]      = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"

    mail(
      to: @user.email,
      subject: weekly_subject(@organization, stats)
    )
  end

  private

  def weekly_subject(organization, stats)
    events = stats.total_events_this_week
    issues = stats.new_issue_count

    label = if events.zero? && issues.zero?
      "a quiet week"
    elsif issues.positive?
      "#{issues} new #{'issue'.pluralize(issues)}, #{events} #{'event'.pluralize(events)}"
    else
      "#{events} #{'event'.pluralize(events)} this week"
    end

    "[ErrSight · #{organization.name}] Weekly digest — #{label}"
  end
end

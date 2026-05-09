class AlertMailer < ApplicationMailer
  def error_alert(user, event, project)
    @user = user
    @event = event
    @project = project
    @event_url = project_event_url(project, event)

    # Strip CRLF before truncation so a customer error message containing a
    # newline can't split the Subject header on older mail agents.
    safe_message = event.message.to_s.gsub(/[\r\n]+/, " ").truncate(80)

    mail(
      to: user.email,
      subject: "[ErrSight · #{project.name}] #{event.level.capitalize}: #{safe_message}"
    )
  end

  def digest_alert(user, events, project, period)
    @user = user
    @events = events
    @project = project
    @period = period
    @project_url = project_events_url(project)

    mail(
      to: user.email,
      subject: "[ErrSight · #{project.name}] #{events.count} new errors (#{period})"
    )
  end
end

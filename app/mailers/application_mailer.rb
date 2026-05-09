class ApplicationMailer < ActionMailer::Base
  # `from` is mandatory; `reply_to` defaults to the same address unless the
  # operator sets SUPPORT_EMAIL to route replies somewhere staffed.
  default from:     ENV.fetch("MAILER_FROM", "no-reply@errsight.local"),
          reply_to: ENV["SUPPORT_EMAIL"].presence || ENV.fetch("MAILER_FROM", "no-reply@errsight.local")
  layout "mailer"

  # Make event-frame helpers available to mailer views so error_alert can
  # render a friendly "raised in app/foo.rb:42 in bar" line instead of an
  # absolute-path backtrace string.
  helper EventFramesHelper
end

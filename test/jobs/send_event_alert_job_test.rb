require "test_helper"

class SendEventAlertJobTest < ActiveJob::TestCase
  setup do
    @event = events(:error_event)
    @project = @event.project
    membership = memberships(:regular_admin)
    AlertPreference.create!(
      membership: membership, project: nil,
      email_enabled: true, slack_enabled: false,
      min_level: Event.levels[:warning], digest_frequency: :immediate
    )
  end

  test "enqueues AlertMailer for immediate email preferences" do
    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      SendEventAlertJob.perform_now(@event.id)
    end
  end

  # Mute-rule coverage now lives in ProcessEventJobTest — the mute check was
  # lifted into the ingestion path so we don't re-query MuteRule per alert job.
end

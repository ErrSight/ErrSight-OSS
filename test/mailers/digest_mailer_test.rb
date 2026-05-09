require "test_helper"

class DigestMailerTest < ActionMailer::TestCase
  test "weekly raises when stats organization does not match membership organization" do
    membership        = memberships(:regular_admin)
    foreign_org_stats = WeeklyDigestStats.new(organizations(:admin_org))

    assert_raises(ArgumentError) do
      DigestMailer.weekly(membership, foreign_org_stats).message
    end
  end

  test "weekly succeeds when stats and membership share the same organization" do
    membership = memberships(:regular_admin)
    stats      = WeeklyDigestStats.new(membership.organization)

    email = DigestMailer.weekly(membership, stats)

    assert_equal [ membership.user.email ], email.to
    assert_includes email.subject, membership.organization.name
  end

  test "rendered email reports the recipient organization's exact stats" do
    membership   = memberships(:admin_admin)
    organization = membership.organization
    project      = projects(:admin_project)

    Event.where(project: project).destroy_all

    fingerprint = "fp-mailer-#{SecureRandom.hex(4)}"
    Event.create!(project: project, level: :error,   message: "first",  environment: "production",
                  occurred_at: 1.day.ago,  fingerprint: fingerprint, size_bytes: 100, discarded: false, metadata: {})
    Event.create!(project: project, level: :error,   message: "second", environment: "production",
                  occurred_at: 2.days.ago, fingerprint: fingerprint, size_bytes: 100, discarded: false, metadata: {})
    Event.create!(project: project, level: :warning, message: "third",  environment: "production",
                  occurred_at: 3.days.ago, fingerprint: "fp-other-#{SecureRandom.hex(4)}",
                  size_bytes: 100, discarded: false, metadata: {})

    stats = WeeklyDigestStats.new(organization)
    email = DigestMailer.weekly(membership, stats)

    text = email.text_part.body.decoded
    html = email.html_part.body.decoded

    assert_equal 3, stats.total_events_this_week
    assert_includes text, "This week:   3 events"
    assert_match(/\b3\b\s*<\/div>\s*<div[^>]*>\s*Events/, html)

    assert_includes text, organization.name
    assert_includes html, organization.name

    refute_includes text, organizations(:regular_org).name
    refute_includes html, organizations(:regular_org).name
    refute_includes text, projects(:alpha).name
    refute_includes html, projects(:alpha).name
  end

  test "top issue link uses the fingerprint, matching the routes :fingerprint param" do
    membership   = memberships(:admin_admin)
    organization = membership.organization
    project      = projects(:admin_project)

    Event.where(project: project).destroy_all

    fingerprint = "fp-link-#{SecureRandom.hex(8)}"
    Event.create!(project: project, level: :error, message: "Linked top issue",
                  environment: "production", occurred_at: 1.day.ago, fingerprint: fingerprint,
                  size_bytes: 100, discarded: false, metadata: {})
    issue = Issue.find_or_create_by!(project: project, fingerprint: fingerprint)

    refute_equal issue.id.to_s, issue.fingerprint, "test relies on id and fingerprint differing"

    stats = WeeklyDigestStats.new(organization)
    html  = DigestMailer.weekly(membership, stats).html_part.body.decoded

    expected_url = Rails.application.routes.url_helpers.project_issue_url(
      project, fingerprint, host: Rails.application.config.action_mailer.default_url_options[:host]
    )
    assert_includes html, expected_url
    assert_match %r{/projects/#{project.id}/issues/#{Regexp.escape(fingerprint)}\b}, html
    refute_match  %r{/projects/#{project.id}/issues/#{issue.id}\b}, html,
                  "must not link to the issue id — the route :fingerprint constraint won't match it"
  end
end

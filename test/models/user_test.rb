require "test_helper"

class UserTest < ActiveSupport::TestCase
  include StubHelper

  # ── Validations ──────────────────────────────────────────────────────────────

  test "valid with required attributes" do
    user = User.new(
      email: "new@example.com",
      name: "New User",
      password: "secret123"
    )
    assert user.valid?
  end

  test "invalid without email" do
    user = users(:regular).dup
    user.email = ""
    assert_not user.valid?
    assert_includes user.errors[:email], "can't be blank"
  end

  test "invalid without name on create" do
    user = User.new(email: "noname@example.com", password: "secret123")
    assert_not user.valid?
    assert_includes user.errors[:name], "can't be blank"
  end

  test "invalid with duplicate email" do
    user = User.new(
      email: users(:regular).email,
      name: "Dupe",
      password: "secret123"
    )
    assert_not user.valid?
    assert_includes user.errors[:email], "has already been taken"
  end

  test "rejects reserved email domains outside test env" do
    stub_method(Rails, :env, ActiveSupport::StringInquirer.new("production")) do
      %w[example.com example.net example.org].each do |domain|
        user = User.new(email: "someone@#{domain}", name: "Reserved", password: "secret123")
        assert_not user.valid?, "expected #{domain} to be rejected"
        assert_includes user.errors[:email], "domain is not allowed"
      end
    end
  end

  # ── admin? ───────────────────────────────────────────────────────────────────

  test "admin? returns true for admin user" do
    assert users(:admin).admin?
  end

  test "admin? returns false for regular user" do
    assert_not users(:regular).admin?
  end

  # ── primary_organization ────────────────────────────────────────────────────

  test "primary_organization returns the first membership's organization" do
    assert_equal organizations(:regular_org), users(:regular).primary_organization
  end

  # ── from_omniauth ───────────────────────────────────────────────────────────

  test "from_omniauth creates a new user" do
    auth = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: "google-123",
      info: { email: "oauth@example.com", name: "OAuth User" }
    )

    assert_difference "User.count", 1 do
      user = User.from_omniauth(auth)

      assert_equal "oauth@example.com", user.email
      assert_equal "OAuth User", user.name
      assert_equal "google_oauth2", user.provider
      assert_equal "google-123", user.uid
      assert user.persisted?
    end
  end

  test "from_omniauth links an existing email account" do
    user = users(:regular)
    auth = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "github-123",
      info: { email: user.email, name: "GitHub User" }
    )

    assert_no_difference "User.count" do
      returned = User.from_omniauth(auth)

      assert_equal user, returned
      assert_equal "github", returned.provider
      assert_equal "github-123", returned.uid
      assert_equal "GitHub User", returned.name
    end
  end

  test "from_omniauth creates a fallback email when provider omits email" do
    auth = OmniAuth::AuthHash.new(
      provider: "github",
      uid: "private-email-user",
      info: { email: nil, name: "Private Email User" }
    )

    user = User.from_omniauth(auth)

    assert_equal "github-private-email-user@oauth.errsight.local", user.email
    assert user.persisted?
  end

  # ── Discard / undiscard cascade ─────────────────────────────────────────────

  test "after_discard cascades to solo-owned organizations" do
    user = users(:regular)
    org  = organizations(:regular_org)
    assert_nil org.discarded_at

    user.discard!

    assert_not_nil org.reload.discarded_at
  end

  test "after_discard does not cascade to shared-owned organizations" do
    user = users(:regular)
    org  = organizations(:regular_org)
    Membership.create!(user: users(:admin), organization: org, role: :member)

    user.discard!

    assert_nil org.reload.discarded_at
  end

  test "after_undiscard un-pauses the user's projects" do
    user = users(:regular)
    project = projects(:alpha)
    user.discard!
    assert project.reload.ingestion_paused

    user.undiscard

    assert_not project.reload.ingestion_paused
  end

  test "solo_owned_organizations excludes shared orgs" do
    user = users(:regular)
    org  = organizations(:regular_org)
    assert_includes user.solo_owned_organizations, org

    Membership.create!(user: users(:admin), organization: org, role: :member)

    assert_not_includes user.solo_owned_organizations, org
    assert_includes user.shared_owned_organizations, org
  end
end

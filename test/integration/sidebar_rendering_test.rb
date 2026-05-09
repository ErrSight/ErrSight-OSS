require "test_helper"

# The sidebar renders in the app layout on EVERY authenticated page, so a bug
# there (like the unsaved-@organization crash that shipped despite a green
# suite) breaks many pages at once while no single action-level test notices.
# These exercise the sidebar across the org states that change how it renders.
class SidebarRenderingTest < ActionDispatch::IntegrationTest
  def user_with_orgs(email, orgs: 1)
    user = User.create!(name: "U", email: email, password: "password123",
                        password_confirmation: "password123",
                        confirmed_at: Time.current)
    orgs.times do |i|
      org = Organization.create!(name: "#{email.split('@').first.capitalize} Org #{i + 1}",
                                 owner: user)
      Membership.create!(organization: org, user: user, role: :admin)
    end
    user
  end

  test "single-org user: dashboard renders with the org switcher" do
    sign_in user_with_orgs("single@sidebar.test")
    get dashboard_path
    assert_response :success
    assert_select "aside.sidebar"
    assert_select ".sb-orgswitch-trigger", 1
  end

  test "multi-org user: the switcher popover lists every org" do
    user = user_with_orgs("multi@sidebar.test", orgs: 3)
    sign_in user
    get dashboard_path
    assert_response :success
    assert_select ".sb-orgswitch-trigger", 1
    user.organizations.kept.each do |org|
      assert_match Regexp.new(Regexp.escape(org.name)), response.body
    end
  end

  test "no-org user: sidebar falls back to the account menu, no switcher, no crash" do
    user = User.create!(name: "Orgless", email: "noorg@sidebar.test", password: "password123",
                        password_confirmation: "password123",
                        confirmed_at: Time.current)
    sign_in user
    get edit_user_registration_path
    assert_response :success
    assert_select "aside.sidebar"
    assert_select ".sb-orgswitch-trigger", 0   # no org -> no switcher
    assert_match(/Sign out/, response.body)      # account actions still reachable
  end

  test "new-org form renders the sidebar (unsaved @organization)" do
    sign_in user_with_orgs("neworg@sidebar.test")
    get new_organization_path
    assert_response :success
    assert_select "aside.sidebar"
  end

  test "failed org create re-renders with a working sidebar (unsaved @organization)" do
    sign_in user_with_orgs("failcreate@sidebar.test")
    assert_no_difference -> { Organization.count } do
      post organizations_path, params: { organization: { name: "" } }
    end
    assert_response :unprocessable_entity
    assert_select "aside.sidebar"
  end

  test "project page renders the project switcher" do
    user    = user_with_orgs("projpage@sidebar.test")
    org     = user.organizations.kept.first
    project = Project.create!(name: "switch-proj", organization: org, user: user)
    sign_in user
    get groups_project_events_path(project)
    assert_response :success
    assert_select ".sb-projswitch-trigger", 1
  end
end

# Community Edition seed data.
#
# This script is idempotent — re-running won't create duplicates.
#
# An initial admin user is bootstrapped from the ADMIN_EMAIL and
# ADMIN_PASSWORD env vars. Set these in your .env or pass them on the
# command line:
#
#     ADMIN_EMAIL=you@example.com ADMIN_PASSWORD=secret bin/rails db:seed
#
# If those vars are not set, the seed runs as a no-op — register through
# the sign-up form instead.

admin_email    = ENV["ADMIN_EMAIL"].to_s.strip.presence
admin_password = ENV["ADMIN_PASSWORD"].to_s.strip.presence

unless admin_email && admin_password
  puts "Skipping seed: set ADMIN_EMAIL and ADMIN_PASSWORD env vars to bootstrap an admin user."
  exit 0
end

admin = User.find_or_initialize_by(email: admin_email)

if admin.new_record?
  admin.assign_attributes(
    password:              admin_password,
    password_confirmation: admin_password,
    name:                  ENV["ADMIN_NAME"].presence || "Admin",
    admin:                 true
  )
  admin.skip_confirmation!
  admin.save!
  puts "Created admin user: #{admin.email}"
else
  admin.update!(admin: true) unless admin.admin?
  puts "Admin user exists: #{admin.email}"
end

org = Organization.find_or_create_by!(owner: admin) do |o|
  o.name = ENV["ADMIN_ORG_NAME"].presence || "#{admin.name}'s Organization"
end

Membership.find_or_create_by!(organization: org, user: admin) do |m|
  m.role = :admin
end
puts "Admin organization: #{org.name}"

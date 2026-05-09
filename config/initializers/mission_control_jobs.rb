# mission_control-jobs ships with HTTP basic auth on by default. We mount the
# engine inside a Devise `authenticated :user, ->(u) { u.admin? }` block in
# routes.rb, which already enforces "must be a signed-in admin." Stacking
# basic auth on top would force a second login at /jobs every session for no
# additional security, so disable the gem's built-in challenge.
#
# Setting the mattr directly (rather than via `config.mission_control.jobs.*`)
# is intentional: the engine copies that ordered-options hash to mattrs in a
# `before_initialize` hook, which runs before app initializers, so a config
# assignment here would be ignored. The basic-auth before_action reads the
# mattr at request time, so a direct assignment is the simplest fix.
MissionControl::Jobs.http_basic_auth_enabled = false

Rails.application.routes.draw do
  devise_for :users, controllers: {
    omniauth_callbacks: "users/omniauth_callbacks",
    registrations:      "users/registrations",
    confirmations:      "users/confirmations"
  }

  # Post-signup landing — "Check your email" with resend
  get "check_email", to: "pages#check_email", as: :check_email

  ActiveAdmin.routes(self)

  # Stop admin-user impersonation started from ActiveAdmin.
  delete "impersonate", to: "impersonations#destroy", as: :stop_impersonating

  # Web UI for Solid Queue (mission_control-jobs). Mounted inside Devise's
  # `authenticated` block keyed on User#admin? — non-authenticated users get
  # bounced to sign-in, non-admin users get a 404 because the route block
  # doesn't match for them. Job arguments are visible here, including
  # ProcessEventJob payloads with PII; keep this admin-only.
  authenticated :user, ->(u) { u.admin? } do
    mount MissionControl::Jobs::Engine, at: "/jobs"
  end

  root to: "pages#landing"

  # Devise's named helper for the post-login destination. Points at /dashboard
  # rather than "/" so callers like `redirect_to authenticated_root_path` land
  # users on the actual app surface in one hop instead of bouncing through "/".
  direct(:authenticated_root) { route_for(:dashboard) }

  get "docs",         to: "pages#docs",         as: :docs
  get "integrations", to: "pages#integrations", as: :integrations
  get "support",      to: "pages#support",      as: :support
  get "privacy",      to: "pages#privacy",      as: :privacy
  get "terms",        to: "pages#terms",        as: :terms

  get "sitemap.xml", to: "pages#sitemap", as: :sitemap, defaults: { format: :xml }
  get "dashboard", to: "dashboard#index", as: :dashboard
  get "search",    to: "search#show",     as: :search
  resources :saved_filters, only: [ :create, :destroy ]

  # One-click weekly digest unsubscribe (signed token, no auth required)
  get  "digest/unsubscribe", to: "digest_subscriptions#destroy", as: :digest_unsubscribe
  post "digest/unsubscribe", to: "digest_subscriptions#destroy"

  # Organizations and team management
  resources :organizations, only: [ :new, :create, :show, :edit, :update ] do
    member do
      post :slack_test
      post :activate
    end
    resources :memberships, only: [ :index, :update, :destroy ]
    resources :invitations, only: [ :create, :destroy ] do
      member do
        post :resend
      end
    end
  end

  # Public invitation acceptance (token-based, no auth required)
  get "invitations/:token",         to: "invitations#show",    as: :invitation_show
  match "invitations/:token/accept", to: "invitations#accept",  as: :accept_invitation, via: [ :get, :post ]
  post "invitations/:token/decline", to: "invitations#decline", as: :decline_invitation

  # Alert preferences per organization
  resources :alert_preferences, only: [ :edit, :update ]

  # Per-membership weekly digest subscription toggle
  patch "memberships/:id/weekly_digest", to: "memberships#update_weekly_digest", as: :toggle_weekly_digest

  resources :projects do
    member do
      post :rotate_api_key
      get :time_series
    end

    resources :events, only: [ :index, :show, :destroy ] do
      collection do
        get :groups
        get :logs
        get :export
        patch :resolve_group
        patch :unresolve_group
        post :mute_group
        delete :unmute_group
        post :bulk
      end
      member do
        patch :resolve
        patch :unresolve
      end
    end

    resources :alert_rules, only: [ :index, :new, :create, :edit, :update, :destroy ]
    resources :webhook_endpoints, only: [ :index, :new, :create, :edit, :update, :destroy ]
    resources :api_keys, only: [ :index, :create, :destroy ]
    resource  :data_erasure, only: [ :new, :create ]

    resources :issues, only: [ :show, :update ], param: :fingerprint, constraints: { fingerprint: /[^\/]+/ } do
      resources :comments, only: [ :create, :destroy ], controller: "issue_comments"
    end
  end

  # API namespace
  namespace :api do
    namespace :v1 do
      get  "events",     to: "events_read#index",  as: :events
      post "events",     to: "events#create"
      get  "events/:id", to: "events_read#show",   as: :event, constraints: { id: /\d+/ }
      get  "issues/:fingerprint", to: "issues#show", as: :issue, constraints: { fingerprint: /[^\/]+/ }
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end

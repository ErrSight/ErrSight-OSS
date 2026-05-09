# Be sure to restart your server when you modify this file.

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data  # brand fonts are self-hosted woff2 (app/assets/fonts); no Google Fonts CDN
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self, "https://challenges.cloudflare.com"
    policy.style_src   :self, :unsafe_inline  # :unsafe_inline required by ActiveAdmin / Tailwind inline styles
    policy.connect_src :self, "https://challenges.cloudflare.com"
    policy.frame_src   :self, "https://challenges.cloudflare.com"
  end

  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end

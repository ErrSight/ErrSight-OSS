# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
Rails.application.config.filter_parameters += [
  :passw, :email, :secret, :token, :_key, :crypt, :salt, :certificate,
  :otp, :ssn, :cvv, :cvc, :authorization, :cookie, :session,
  :reset_password_token, :confirmation_token, :unlock_token, :invitation_token,
  :slack_webhook_url, :webhook_url, :api_key, :api_token, :access_token, :refresh_token,
  :card_number, :card, :iban, :account_number,
  :user_context, :backtrace, :breadcrumbs, :user_identifier, :exit_details, :details,
  :webhook_endpoint
]

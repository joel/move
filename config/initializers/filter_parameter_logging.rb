# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# `key` and `credential` cover passwordless auth secrets that substring-matching
# would otherwise miss: Rodauth's email-auth / verify-account magic-link `key`
# (`"key".include?("_key")` is false) and the Google One Tap `credential` ID token
# (#492). `key` subsumes `_key`; both kept for clarity.
Rails.application.config.filter_parameters += %i[
  passw email secret token key credential _key crypt salt certificate otp ssn cvv cvc
]

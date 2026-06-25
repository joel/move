# frozen_string_literal: true

require "digest"

# A single-use, short-lived token that hands an authenticated identity from the
# apex host to an org subdomain (#280). Cookies are host-only, so the apex
# session does not travel to `<slug>.<zone>`; instead the apex mints one of these
# tokens (bound to a user + target tenant), redirects to the subdomain with the
# raw value, and the subdomain exchanges it for its own host-only session.
#
# Lives in the `public` schema (excluded Apartment model) because the apex (no
# tenant) mints it and a subdomain (tenant active) consumes it. Only the SHA-256
# digest is persisted, so the raw token is recoverable only from the redirect URL
# and a leaked row cannot be replayed.
#
# Minting/consuming/validation live in app/actions/session_handoffs; this model
# stays persistence-focused (digesting, scopes, the lookup finder).
class SessionHandoffToken < ApplicationRecord
  # How long a freshly minted token stays valid. Deliberately tiny: the legit
  # flow consumes it within milliseconds of the post-auth redirect, so a short
  # window minimises the replay/login-CSRF surface.
  TTL = 60.seconds

  # user_id references public.users across schemas; no DB foreign key.
  belongs_to :user, inverse_of: false

  validates :token_digest, presence: true, uniqueness: true
  validates :organization_slug, presence: true
  validates :expires_at, presence: true

  # Spent rows the daily sweep (PurgeStaleSessionHandoffTokensJob) reaps: expired
  # (TTL is 60s, so almost immediately) or already consumed.
  scope :purgeable, -> { where("expires_at <= ? OR consumed_at IS NOT NULL", Time.current) }

  # Generate a fresh raw token. Returned to the caller once; never stored.
  def self.generate_raw_token
    SecureRandom.urlsafe_base64(32)
  end

  # SHA-256 hex digest of a raw token — persisted on mint, recomputed on consume
  # for a single indexed lookup (not a per-row compare).
  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def expired?
    expires_at <= Time.current
  end

  def consumed?
    consumed_at.present?
  end
end

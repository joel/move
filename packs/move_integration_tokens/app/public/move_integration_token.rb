# frozen_string_literal: true

require "digest"

# A revocable per-Move MCP integration token (Domain §4.13, Technical Foundation
# §14). Lives in the tenant schema; scoped to exactly one Move. An MCP client
# presents the raw token as an HTTP bearer credential; only the SHA-256 digest is
# persisted, so the raw value is shown once at creation and never recoverable.
#
# Revoking a token does not touch who can sign in to the web app. The reverse is
# NOT independent: a token is only valid while its creator is an admin of the Move
# (minting/revoking is admin-only), so removing the member — or demoting them out
# of admin — revokes their tokens (deprovisioning; see
# MoveMemberships::TokenRevocation). A revoked token fails auth.
#
# Minting, revoking, and the audit trail belong in app/actions, not here; this
# model stays persistence-focused (digesting, scopes, the auth finder).
class MoveIntegrationToken < ApplicationRecord
  # Raw tokens are prefixed so they are recognisable in logs/leaks and so a
  # paste of the wrong string fails fast. The secret is 32 url-safe bytes.
  TOKEN_PREFIX = "mcp_"

  belongs_to :move
  # created_by references public.users across schemas; no DB foreign key.
  belongs_to :created_by, class_name: "User", foreign_key: :created_by_user_id, inverse_of: false

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(revoked_at: nil) }

  # Generate a fresh raw token. Returned to the caller once; never stored.
  def self.generate_raw_token
    "#{TOKEN_PREFIX}#{SecureRandom.urlsafe_base64(32)}"
  end

  # SHA-256 hex digest of a raw token. Used both to persist on create and to
  # look the token up on auth (constant-table lookup, not a per-row compare).
  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  # Resolve a presented raw bearer token to its active (non-revoked) record
  # within the current tenant schema, or nil. The unique digest index makes this
  # a single indexed lookup; a blank/garbage token simply misses.
  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    active.find_by(token_digest: digest(raw_token))
  end

  def revoked?
    revoked_at.present?
  end

  # Record that the token was just used for an MCP request. Best-effort and
  # outside the auth decision, so a write race never blocks a valid call.
  def touch_last_used!
    update_column(:last_used_at, Time.current) # rubocop:disable Rails/SkipsModelValidations
  end
end

# frozen_string_literal: true

# Single-use apex->subdomain session-handoff tokens (#280). Lives in `public`
# (an excluded Apartment model, like Organization) because it bridges identity
# between the apex host and an org subdomain, which now hold *host-only* cookies
# and therefore no longer share a session. The raw token travels in the redirect
# URL; only its SHA-256 digest is persisted, so a leaked row cannot be replayed.
class CreateSessionHandoffTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :session_handoff_tokens, id: :uuid, if_not_exists: true do |t|
      # SHA-256 hex digest of the raw secret (never store the raw token).
      t.string :token_digest, null: false
      # The account the token authenticates. References public.users across
      # schemas, so no DB foreign key (mirrors move_integration_tokens).
      t.uuid :user_id, null: false
      # The org subdomain (Apartment tenant) the token is valid for; the consume
      # path rejects a token presented on any other tenant.
      t.citext :organization_slug, null: false
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end
    add_index :session_handoff_tokens, :token_digest, unique: true, if_not_exists: true
    # Sweep expired/consumed rows efficiently.
    add_index :session_handoff_tokens, :expires_at, if_not_exists: true
  end
end

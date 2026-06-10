class CreateMoveIntegrationTokens < ActiveRecord::Migration[8.1]
  # D13 / Phase 10 — per-Move MCP integration tokens (Domain §4.13). A revocable
  # bearer token that lets an MCP assistant act on exactly one Move through the
  # same shared actions as the web app. Lives in the tenant schema like every
  # Move-owned record, so it is scoped by move_id (org == schema under Apartment).
  #
  # Only the SHA-256 digest is stored; the raw token is shown once at creation.
  def change
    create_table :move_integration_tokens, id: :uuid, if_not_exists: true do |t|
      # Same-schema FK: integration tokens and moves are cloned together per tenant.
      t.references :move, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      # Denormalized for scoping/audit. References public.organizations; the org
      # *is* the Apartment schema, so there is no cross-schema FK.
      t.uuid :organization_id, null: false
      # References public.users (the admin who minted it); no cross-schema FK.
      t.uuid :created_by_user_id, null: false
      t.string :name, null: false
      t.string :token_digest, null: false
      t.datetime :revoked_at
      t.datetime :last_used_at
      # Optional future narrowing of the tool set; Phase 1 uses the fixed set.
      t.jsonb :permissions, null: false, default: {}

      t.timestamps
    end
    add_index :move_integration_tokens, :token_digest, unique: true
    add_index :move_integration_tokens, :created_by_user_id
  end
end

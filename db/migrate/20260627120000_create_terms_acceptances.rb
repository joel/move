# frozen_string_literal: true

# Per-account acceptance of the versioned legal risk-acknowledgement (#369).
# Lives in `public` (an excluded Apartment model, like User/SessionHandoffToken)
# because it records identity-level state that must resolve identically from the
# apex (no tenant) and from any org subdomain (tenant active). Append-only audit
# trail: one row per (account, terms_version), so a future terms-version bump
# re-gates every account without discarding the record of prior acceptances.
class CreateTermsAcceptances < ActiveRecord::Migration[8.1]
  def change
    create_table :terms_acceptances, id: :uuid, if_not_exists: true do |t|
      # The account that accepted. Both this table and `users` are excluded
      # Apartment models (public-only), so the FK lives in public and is never
      # cloned into a tenant schema. ON DELETE CASCADE reaps acceptances when
      # Accounts::Delete removes the user row.
      t.uuid :user_id, null: false
      # Date-stamped terms version accepted (e.g. "2026-06-27"). See Terms.
      t.string :terms_version, null: false
      t.datetime :accepted_at, null: false
      # Best-effort request provenance for the legal record (nullable).
      t.string :ip_address
      t.string :user_agent

      t.timestamps
    end

    # One acceptance per account per version — makes re-accept idempotent and the
    # gate's existence check an indexed lookup.
    add_index :terms_acceptances, %i[user_id terms_version], unique: true,
                                                             if_not_exists: true
    add_foreign_key :terms_acceptances, :users, on_delete: :cascade
  end
end

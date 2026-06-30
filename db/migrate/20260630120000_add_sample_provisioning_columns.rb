# frozen_string_literal: true

# Two columns powering the "auto-provision a sample Move on signup" feature (#432):
#
#   moves.sample (tenant table) — marks the curated onboarding sample Move so the
#     "Remove sample" affordance can target it.
#   organizations.demo_data_status (public/excluded table) — nil (never run) /
#     "provisioning" / "provisioned" / "failed". Drives the Moves-index live-reveal
#     placeholder without needing a Move row to exist yet, and anchors the stream.
#
# Both use `if_not_exists: true` so the migration is safe under Apartment's
# `apartment:migrate` (which replays every migration against the public schema AND
# each tenant schema). `moves` is cloned into every tenant, so the column is added
# there directly. `organizations` is an excluded model present only in `public`;
# because `public` stays on the search path (persistent_schemas), the ALTER from a
# tenant run resolves to `public.organizations` and `if_not_exists` makes every run
# after the first a no-op — the column is never duplicated into a tenant schema.
class AddSampleProvisioningColumns < ActiveRecord::Migration[8.1]
  def change
    add_column :moves, :sample, :boolean, null: false, default: false, if_not_exists: true
    add_column :organizations, :demo_data_status, :string, if_not_exists: true
  end
end

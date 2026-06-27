# frozen_string_literal: true

# One account's acceptance of a single version of the legal risk-acknowledgement
# (#369). Append-only: one row per (user, terms_version). Lives in `public` (an
# excluded Apartment model) so it resolves identically from the apex and from any
# org subdomain. The gate (TenantController#require_terms_agreement!) and the
# writer (Terms::Accept) own the logic; this model stays persistence-focused.
class TermsAcceptance < ApplicationRecord
  # user_id references public.users; both are excluded (public-only) models, so
  # the FK lives in public. inverse_of: false — User#terms_acceptances is a plain
  # has_many with no reciprocal needed here.
  belongs_to :user, inverse_of: :terms_acceptances

  validates :terms_version, presence: true
  validates :accepted_at, presence: true
  # Uniqueness of (user_id, terms_version) is enforced by the DB unique index, NOT
  # an AR validation — deliberately. Terms::Accept upserts via create_or_find_by!,
  # which depends on the database raising RecordNotUnique to converge concurrent /
  # repeat accepts onto one row; an AR uniqueness validation would instead raise
  # RecordInvalid first and defeat that idempotency.
end

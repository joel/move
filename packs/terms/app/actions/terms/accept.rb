# frozen_string_literal: true

# pack_public: true -- public API of packs/terms: AgreementsController calls Terms::Accept.
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module Terms
  # Records an account's acceptance of the current terms version (#369).
  # Idempotent: re-accepting the same version returns the existing row as a
  # Success (handles a double-submit and the create/find race via the unique
  # index). Emits `terms.accepted`.
  class Accept < BaseAction
    def call(user:, ip: nil, user_agent: nil)
      acceptance = yield persist(user, ip, user_agent)
      yield emit_event(acceptance)
      Success(acceptance)
    end

    private

    # create_or_find_by! atomically inserts, or falls back to the existing row on
    # the unique-index violation — so concurrent/duplicate accepts converge on one
    # row instead of raising. The block runs only on insert.
    def persist(user, ip, user_agent)
      acceptance = TermsAcceptance.create_or_find_by!(
        user_id: user.id,
        terms_version: Terms::CURRENT_VERSION
      ) do |record|
        record.accepted_at = Time.current
        record.ip_address = ip
        record.user_agent = user_agent
      end
      Success(acceptance)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(acceptance)
      Rails.event.notify(
        "terms.accepted",
        user_id: acceptance.user_id,
        terms_version: acceptance.terms_version
      )
      Success()
    end
  end
end

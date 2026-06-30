# frozen_string_literal: true

module SessionHandoffs
  # Validate and consume an apex->subdomain handoff token (#280) on the org
  # subdomain. Enforces the token invariants — exists, not expired, not already
  # used, and minted for THIS tenant — and atomically claims it (single-use), then
  # returns the bound user. Establishing the session and the final active-account
  # gate stay in the controller (which holds the Rodauth instance).
  #
  # `organization_slug` is the request's active tenant; a token minted for another
  # org is rejected, so a leaked/replayed token cannot cross tenants.
  class Consume < BaseAction
    def call(raw_token:, organization_slug:)
      token = yield find(raw_token)
      yield validate(token, organization_slug)
      yield claim(token)
      user = yield resolve_user(token)
      yield emit_event(token, user)
      Success(user)
    end

    private

    def find(raw_token)
      return Failure(:invalid) if raw_token.blank?

      token = SessionHandoffToken.find_by(token_digest: SessionHandoffToken.digest(raw_token))
      token ? Success(token) : Failure(:invalid)
    end

    # Cheap pre-checks before the atomic claim, so the failure reason is precise
    # (expired vs already-used vs wrong-tenant). Slugs are normalised lowercase;
    # compare case-insensitively to match the citext column.
    def validate(token, organization_slug)
      return Failure(:already_used) if token.consumed?
      return Failure(:expired) if token.expired?

      same_tenant = token.organization_slug.to_s.casecmp?(organization_slug.to_s)
      return Failure(:wrong_tenant) unless same_tenant

      Success()
    end

    # Single-use is enforced HERE, atomically: only the first caller to flip
    # consumed_at from NULL wins, so two concurrent requests with the same token
    # can never both establish a session. A 0-row result means it was claimed
    # between #validate and now.
    def claim(token)
      # rubocop:disable Rails/SkipsModelValidations -- atomic single-use claim:
      # the WHERE consumed_at IS NULL lets exactly one caller win; an AR callback
      # path would reintroduce the read-then-write race this guards against.
      claimed = SessionHandoffToken
                .where(id: token.id, consumed_at: nil)
                .update_all(consumed_at: Time.current)
      # rubocop:enable Rails/SkipsModelValidations
      claimed == 1 ? Success() : Failure(:already_used)
    end

    def resolve_user(token)
      user = User.find_by(id: token.user_id)
      user ? Success(user) : Failure(:invalid)
    end

    def emit_event(token, user)
      Rails.event.notify(
        "session_handoff.consumed",
        token_id: token.id,
        user_id: user.id,
        organization_slug: token.organization_slug
      )
      Success()
    end
  end
end

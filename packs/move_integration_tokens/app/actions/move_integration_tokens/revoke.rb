# frozen_string_literal: true

# pack_public: true -- public API of packs/move_integration_tokens: revokes an integration token (IntegrationTokensController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveIntegrationTokens
  # Revokes a per-Move MCP integration token (D13 / Phase 10). Sets revoked_at so
  # the next MCP auth attempt fails (MoveIntegrationToken.authenticate only
  # resolves active tokens). Revocation is independent of MoveMembership.
  #
  # Idempotent: revoking an already-revoked token succeeds without re-stamping or
  # re-emitting, so a double-submit is harmless. The caller (controller) owns
  # authorization (admin-only).
  class Revoke < BaseAction
    #: (token: untyped, actor: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(token:, actor:)
      return Success(token) if token.revoked?

      yield persist(token)
      yield emit_event(token, actor)
      Success(token)
    end

    private

    #: (untyped token) -> Dry::Monads::Result[untyped, untyped]
    def persist(token)
      token.update!(revoked_at: Time.current)
      Success(token)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    #: (untyped token, untyped actor) -> Dry::Monads::Success[nil]
    def emit_event(token, actor)
      Rails.event.notify(
        "integration_token.revoked",
        move_id: token.move_id,
        token_id: token.id,
        token_name: token.name,
        actor_id: actor&.id,
        source: Current.source
      )
      Success()
    end
  end
end

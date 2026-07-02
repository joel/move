# frozen_string_literal: true

module MoveMemberships
  # Deprovisioning: an MCP integration token is only valid while its creator is an
  # admin of the Move — minting/revoking tokens is admin-only
  # (MovePolicy#manage_integration_tokens?). So when a member is removed, or
  # demoted out of admin, their active tokens must be revoked; otherwise the
  # departed/demoted user keeps full programmatic read+write access to the Move via
  # their `mcp_…` bearer token (MCP tools authorize on token validity, not live
  # membership/role).
  #
  # Revocation runs INSIDE the membership mutation's transaction (atomic with the
  # removal/role change — if the mutation rolls back, so does the revocation). The
  # audit events are emitted by the caller AFTER commit, never on uncommitted state.
  #
  # Reached through the `move.integration_tokens` association (a method call), so
  # this stays decoupled from packs/move_integration_tokens — no cross-pack
  # constant reference, no new Packwerk dependency edge.
  module TokenRevocation
    private

    # Revoke every active token +user_id+ created on +move+ and return the revoked
    # records (for post-commit event emission). Token counts per user are tiny.
    def revoke_member_tokens(move, user_id)
      now = Time.current
      tokens = move.integration_tokens.active.where(created_by_user_id: user_id).to_a
      tokens.each { |token| token.update!(revoked_at: now) }
      tokens
    end

    # One `integration_token.revoked` event per revoked token, matching
    # MoveIntegrationTokens::Revoke's payload so MoveMcp::AuditSubscriber records it.
    # Call AFTER the mutation commits.
    def emit_token_revocations(tokens, actor)
      tokens.each do |token|
        Rails.event.notify(
          "integration_token.revoked",
          move_id: token.move_id,
          token_id: token.id,
          token_name: token.name,
          actor_id: actor&.id,
          source: Current.source
        )
      end
    end
  end
end

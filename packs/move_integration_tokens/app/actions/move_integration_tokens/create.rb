# frozen_string_literal: true

# pack_public: true -- public API of packs/move_integration_tokens: creates an integration token (IntegrationTokensController).
# Kept in the action layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module MoveIntegrationTokens
  # Mints a per-Move MCP integration token (D13 / Phase 10, Domain §4.13).
  #
  # The raw token is generated here, hashed, and persisted as a digest; the raw
  # value is returned to the caller exactly once (Result#raw_token) so the UI can
  # reveal it a single time. It is never stored and cannot be recovered.
  #
  # The caller (controller) owns authorization — token management is admin-only
  # (MovePolicy#manage_integration_tokens?). organization_id is denormalized from
  # the current Apartment tenant for audit/scoping, mirroring MoveMemberships::Add.
  class Create < BaseAction
    # Returned on success: the persisted record plus the one-time raw token.
    Result = Data.define(:token, :raw_token)

    def call(move:, name:, actor:)
      yield ensure_writable(move)
      yield validate_name(name)
      organization = yield current_organization
      raw_token = MoveIntegrationToken.generate_raw_token
      token = yield persist(move, organization, name, actor, raw_token)
      yield emit_event(token, actor)
      Success(Result.new(token: token, raw_token: raw_token))
    end

    private

    def validate_name(name)
      return Failure(:blank_name) if name.to_s.strip.empty?

      Success()
    end

    def current_organization
      organization = Organization.find_by(slug: Apartment::Tenant.current)
      return Failure(:not_found) if organization.nil?

      Success(organization)
    end

    def persist(move, organization, name, actor, raw_token)
      Success(
        move.integration_tokens.create!(
          organization_id: organization.id,
          created_by: actor,
          name: name.to_s.strip,
          token_digest: MoveIntegrationToken.digest(raw_token)
        )
      )
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    end

    def emit_event(token, actor)
      Rails.event.notify(
        "integration_token.created",
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

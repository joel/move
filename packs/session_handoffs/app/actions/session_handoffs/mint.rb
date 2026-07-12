# frozen_string_literal: true

# pack_public: true -- public API of packs/session_handoffs: mints a single-use handoff token (Rodauth).
# Kept in its layer; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module SessionHandoffs
  # Mint a single-use apex->subdomain handoff token (#280). Called on the apex
  # right after a successful authentication, bound to the authenticated user and
  # the target org subdomain. Returns the RAW token (shown once, in the redirect
  # URL); only its digest is persisted.
  #
  # The mint runs in the `public` schema (the apex has no tenant active);
  # SessionHandoffToken is an excluded Apartment model, so the row lands in public
  # regardless of the caller's schema.
  class Mint < BaseAction
    # return_path: an optional in-tenant destination the consuming subdomain
    # redirects to after establishing the session (D14 invitations land on the
    # Move). The consumer validates it as a safe internal path.

    #: (user: untyped, organization_slug: untyped, ?return_path: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(user:, organization_slug:, return_path: nil)
      raw = SessionHandoffToken.generate_raw_token
      token = yield persist(user, organization_slug, raw, return_path)
      yield emit_event(token)
      Success(raw)
    end

    private

    #: (untyped user, untyped organization_slug, untyped raw, untyped return_path) -> Dry::Monads::Result[untyped, untyped]
    def persist(user, organization_slug, raw, return_path)
      token = SessionHandoffToken.create!(
        user: user,
        organization_slug: organization_slug.to_s,
        token_digest: SessionHandoffToken.digest(raw),
        expires_at: SessionHandoffToken::TTL.from_now,
        return_path: return_path
      )
      Success(token)
    rescue ActiveRecord::RecordInvalid => e
      Failure(e.record.errors)
    rescue ActiveRecord::ActiveRecordError => e
      # Fail SOFT on any other persistence error (constraint, statement,
      # connection): the sole caller (tenant_handoff_url, on the post-auth
      # redirect path) turns a Failure into "stay on the apex" — never raise out
      # of login_redirect and 500 a just-authenticated user. #349 handled the
      # monadic-Failure path; this covers the exception path (#351).
      Failure(e.message)
    end

    #: (untyped token) -> Dry::Monads::Success[nil]
    def emit_event(token)
      Rails.event.notify(
        "session_handoff.minted",
        token_id: token.id,
        user_id: token.user_id,
        organization_slug: token.organization_slug
      )
      Success()
    end
  end
end

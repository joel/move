# frozen_string_literal: true

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
    def call(user:, organization_slug:)
      raw = SessionHandoffToken.generate_raw_token
      token = yield persist(user, organization_slug, raw)
      yield emit_event(token)
      Success(raw)
    end

    private

    def persist(user, organization_slug, raw)
      token = SessionHandoffToken.create!(
        user: user,
        organization_slug: organization_slug.to_s,
        token_digest: SessionHandoffToken.digest(raw),
        expires_at: SessionHandoffToken::TTL.from_now
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

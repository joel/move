# frozen_string_literal: true

# Exchanges a single-use apex->subdomain handoff token (#280) for the org
# subdomain's OWN host-only session. Since cookies are host-only, the apex login
# session does not travel here; the browser arrives unauthenticated carrying only
# the token, so this controller cannot itself require authentication.
#
# CSRF is not applicable: this is a top-level GET navigation whose sole credential
# is the unguessable, single-use, short-TTL token — the same trust model as a
# Rodauth email magic link. Replay is blocked by single-use consumption; a token
# minted for another org is rejected by the tenant check inside the action.
class SessionHandoffsController < ApplicationController
  # Exchanges the token for a session; the terms gate (#369) doesn't apply — the
  # post-handoff redirect to the org home lands on a gated surface that enforces it.
  skip_before_action :require_terms_agreement!, raise: false

  def show
    slug = current_tenant
    return render_expired if slug.blank? # handoff is only meaningful on a tenant subdomain

    result = SessionHandoffs::Consume.new.call(raw_token: params[:token], organization_slug: slug)

    case result
    in Dry::Monads::Success(user)
      establish_session(user)
    in Dry::Monads::Failure(_reason)
      render_expired
    end
  end

  private

  def establish_session(user)
    # A handoff token is only minted right after a successful apex authentication
    # (Rodauth's own open-status gate has already run), so a non-open status here
    # means the account was closed/downgraded within the token's brief lifetime —
    # refuse to establish a session for it.
    return render_expired unless user.status == rodauth.account_open_status_value

    # Session-fixation hygiene: rotate the session before establishing the
    # authenticated identity, so a value planted pre-auth can't survive it (#496).
    # The credential is the handoff token (a URL param), not session state, so
    # nothing of value is lost.
    reset_session
    rodauth.account_from_id(user.id)
    session[rodauth.session_key] = user.id
    session[rodauth.authenticated_by_session_key] = ["session_handoff"]
    # Re-issue a host-only remember cookie on THIS subdomain so persistent login
    # survives per-domain (each host holds its own remember key) — #280.
    rodauth.remember_login
    redirect_to root_path
  end

  def render_expired
    render Views::SessionHandoffs::Expired.new(login_url: apex_login_url),
           status: :unauthorized
  end

  # Absolute apex login URL: a failed handoff has no subdomain session, and the
  # apex is the canonical home of every auth flow. https to match tenant_home_url.
  def apex_login_url
    "https://#{apex_host}#{rodauth.login_path}"
  end
end

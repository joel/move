# frozen_string_literal: true

# Apex landing + accept for Move invitations (Phase D14, #608). The emailed
# link always targets the apex: the recipient has no tenant access until they
# accept (TenantController#require_membership! 404s non-members), so the token
# must resolve where no tenant is active. GET renders the landing for anyone
# holding a live token (anonymous or authenticated); POST performs the accept
# for the authenticated invited email and hands the session off to the org
# subdomain, landing on the joined Move.
#
# Non-disclosure: expired, revoked, consumed, unknown, and wrong-account all
# render ONE generic "unavailable" page with :not_found — a token holder can
# never probe invitation state or account existence beyond their own mailbox.
class InvitationAcceptancesController < ApplicationController
  # Auth-flow surface, like the session handoff: the terms gate belongs to the
  # tenant the invitee is about to enter, not to this apex broker page.
  skip_before_action :require_terms_agreement!, raise: false

  # Hygiene only — the 256-bit token makes brute force moot, but the endpoint is
  # unauthenticated, so bound it per-IP anyway.
  # steep: the Rails 8 rate_limit macro predates the 7.0-era actionpack sigs,
  # so the generated interface lacks it.
  rate_limit to: 20, within: 1.minute, by: -> { request.remote_ip }, with: -> { head :too_many_requests } # steep:ignore NoMethod

  before_action :redirect_to_apex, unless: :on_apex_host?

  #: () -> untyped
  def show
    invitation = resolve_invitation
    return render_unavailable if invitation.nil?

    render Views::Invitations::Show.new(
      invitation: invitation,
      raw_token: params[:token].to_s,
      move_name: move_name_for(invitation),
      state: landing_state(invitation)
    )
  end

  #: () -> untyped
  def create
    return render_unavailable if current_user.nil?

    result = MoveInvitations::Accept.new.call(raw_token: params[:token].to_s, user: current_user)

    case result
    in Dry::Monads::Success({ organization: organization, move_id: move_id })
      hand_off_to(organization, move_id)
    in Dry::Monads::Failure(_reason)
      render_unavailable
    end
  end

  private

  # A landing is shown only to plausible holders: a live invitation for anyone,
  # or an accepted one for the matching signed-in user (the resume path — a
  # re-click after a crash or a lost redirect must not dead-end). Everything
  # else is indistinguishable from an unknown token.

  #: () -> untyped
  def resolve_invitation
    invitation = MoveInvitation.find_by(token_digest: MoveInvitation.digest(params[:token].to_s))
    invitation if invitation && visible_to_holder?(invitation)
  end

  #: (untyped invitation) -> bool
  def visible_to_holder?(invitation)
    return false if invitation.revoked? || invitation.expired?
    return email_match?(invitation) if current_user

    !invitation.accepted?
  end

  #: (untyped invitation) -> bool
  def email_match?(invitation)
    invitation.email.to_s.casecmp?(current_user.email.to_s)
  end

  #: (untyped invitation) -> Symbol
  def landing_state(invitation)
    return :acceptable if current_user
    return :sign_in if User.exists?(email: invitation.email)

    :create_account
  end

  #: (untyped invitation) -> String?
  def move_name_for(invitation)
    Apartment::Tenant.switch(invitation.organization.slug) do
      Move.find_by(id: invitation.move_id)&.name
    end
  rescue Apartment::TenantNotFound
    nil
  end

  # The apex is a pure auth broker (#280): hand the session to the subdomain
  # via a single-use token carrying the Move as the landing path, and drop the
  # apex session. If minting fails, stay on the apex with the session intact —
  # re-clicking the invite link resumes.

  #: (untyped organization, untyped move_id) -> untyped
  def hand_off_to(organization, move_id)
    raw = SessionHandoffs::Mint.new.call(
      user: current_user, organization_slug: organization.slug,
      return_path: "/moves/#{move_id}/boxes"
    ).value_or(nil)
    return redirect_to root_path if raw.nil?

    reset_session
    zone = Rails.application.config.x.tenant_zone
    redirect_to "https://#{organization.slug}.#{zone}/session/handoff?token=#{raw}",
                allow_other_host: true
  end

  #: () -> untyped
  def render_unavailable
    render Views::Invitations::Unavailable.new(signed_in: current_user.present?),
           status: :not_found
  end

  # Be forgiving about the host: the mailed link targets the apex, but a link
  # pasted on a tenant host still works by bouncing to the canonical URL.

  #: () -> untyped
  def redirect_to_apex
    redirect_to "https://#{apex_host}#{request.fullpath}", allow_other_host: true
  end
end

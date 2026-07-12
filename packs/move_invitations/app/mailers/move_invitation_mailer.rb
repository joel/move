# frozen_string_literal: true

# Delivers a Move invitation (Phase D14, #608) — the raw single-use token's only
# home is this email's link. Built in the delivery job (no request, no tenant),
# so everything renders from the public-schema invitation row plus one tenant
# switch for the Move's name. The link targets the APEX host (Action Mailer's
# default_url_options): the recipient has no tenant access until they accept.
class MoveInvitationMailer < ApplicationMailer
  #: (invitation_id: untyped, raw_token: untyped) -> untyped
  def invite(invitation_id:, raw_token:)
    @invitation = MoveInvitation.find(invitation_id)
    @accept_url = invitation_acceptance_url(token: raw_token)
    @move_name = move_name(@invitation)
    @inviter_name = @invitation.invited_by&.name.presence

    mail to: @invitation.email,
         subject: I18n.t("move_invitation_mailer.invite.subject",
                         move: @move_name || @invitation.organization.name)
  end

  private

  # The Move lives in the tenant schema; a Move deleted between enqueue and
  # delivery (or a dropped tenant) degrades to org-name copy, never an error.

  #: (untyped invitation) -> untyped
  def move_name(invitation)
    Apartment::Tenant.switch(invitation.organization.slug) do
      Move.find_by(id: invitation.move_id)&.name
    end
  rescue Apartment::TenantNotFound
    nil
  end
end

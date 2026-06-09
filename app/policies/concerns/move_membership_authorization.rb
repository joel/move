# frozen_string_literal: true

# Shared move-level authorization for policies whose record is (or belongs to) a
# Move. Membership lives in the tenant schema (MoveMembership joins
# public.users to a Move); these helpers resolve the current user's role on a
# given Move so the read/edit/admin split (D11) is expressed in one place.
#
# Role tiers:
#   admin       — full control, incl. member management and vocabulary curation.
#   contributor — read + mutate box/item/recognition content.
#   viewer      — read-only (including the box manifest export).
#
# Reads are already isolated by the Apartment tenant schema and, for nested
# resources, by MovePolicy.relation_scope (a non-member's Move 404s at load), so
# these helpers are both the primary gate for the Move itself and defence in
# depth for its contents.
module MoveMembershipAuthorization
  extend ActiveSupport::Concern

  private

  # The current user's MoveMembership on +move+, or nil. Memoized per Move so a
  # policy checking several predicates issues one query.
  def membership_on(move)
    return nil if user.nil? || move.nil?

    (@membership_on ||= {})[move.id] ||= move.membership_for(user)
  end

  # Any member (admin/contributor/viewer) may read.
  def reader_of?(move)
    membership_on(move).present?
  end

  # Admin or contributor may mutate the Move's content, and only while the Move
  # is writable (non-archived).
  def editor_of?(move)
    membership = membership_on(move)
    return false if membership.nil?

    membership.can_edit? && move.writable?
  end

  # Only an admin may manage members/roles and curate the Move's vocabulary.
  def admin_of?(move)
    membership_on(move)&.admin? || false
  end
end

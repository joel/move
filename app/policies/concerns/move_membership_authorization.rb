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

  # Holds an editing role (admin or contributor) on the Move — independent of
  # whether the Move is currently writable. Used where archived state is handled
  # separately (the controller's archived → read-only redirect).
  def editor_role?(move)
    membership_on(move)&.can_edit? || false
  end

  # May mutate the Move's content *now*: an editing role on a writable
  # (non-archived) Move. The complete rule for authorize! paths.
  def editor_of?(move)
    editor_role?(move) && move.writable?
  end

  # Only an admin may manage members/roles and curate the Move's vocabulary.
  def admin_of?(move)
    membership_on(move)&.admin? || false
  end
end

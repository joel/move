# frozen_string_literal: true

# Joins a User (public schema) to a Move (tenant schema). The creator of a
# Move becomes its admin via Moves::Create.
#
# Roles (D11):
#   admin       — full control, including managing members and roles.
#   contributor — read + mutate the Move's contents (boxes, items, recognition).
#   viewer      — read-only (including the box manifest export).
class MoveMembership < ApplicationRecord
  ROLES = %w[admin contributor viewer].freeze

  belongs_to :move
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :move_id }

  def admin?
    role == "admin"
  end

  def contributor?
    role == "contributor"
  end

  def viewer?
    role == "viewer"
  end

  # Whether this member may mutate the Move's contents (subject to the Move
  # still being writable). Viewers are read-only.
  def can_edit?
    admin? || contributor?
  end
end

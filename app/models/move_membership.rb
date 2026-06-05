# frozen_string_literal: true

# Joins a User (public schema) to a Move (tenant schema). The creator of a
# Move becomes its admin via Moves::Create.
class MoveMembership < ApplicationRecord
  ROLES = %w[admin member].freeze

  belongs_to :move
  belongs_to :user

  validates :role, inclusion: { in: ROLES }
  validates :user_id, uniqueness: { scope: :move_id }
end

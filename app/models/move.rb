# frozen_string_literal: true

# A relocation project. Moves live inside a tenant (Organization) schema, so
# there is no organization_id column — the active Apartment schema *is* the
# tenant. `created_by` and members reference public.users across schemas via
# AR associations (no database foreign key).
#
# State transitions and membership creation belong in app/actions, not here.
class Move < ApplicationRecord
  STATUSES = %w[planned started finished archived].freeze
  UNIT_SYSTEMS = %w[metric imperial].freeze

  belongs_to :created_by, class_name: "User"
  has_many :move_memberships, dependent: :destroy
  has_many :users, through: :move_memberships
  has_many :rooms, dependent: :destroy
  has_many :categories, dependent: :destroy
  has_many :tags, dependent: :destroy
  has_many :boxes, dependent: :destroy
  has_many :media, dependent: :destroy
  has_many :recognition_runs, dependent: :destroy
  has_many :recognition_suggestions, dependent: :destroy
  has_many :items, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :unit_system, inclusion: { in: UNIT_SYSTEMS }

  def archived?
    status == "archived"
  end

  def writable?
    !archived?
  end

  # The membership joining +user+ to this Move, or nil if they are not a
  # member. Used by MovePolicy/BoxPolicy to gate reads and mutations on
  # move-level role (D11).
  def membership_for(user)
    return nil if user.nil?

    move_memberships.find_by(user_id: user.id)
  end
end

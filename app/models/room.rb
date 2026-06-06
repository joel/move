# frozen_string_literal: true

# A minimal room vocabulary scoped to a Move (D2). Rooms label boxes; full
# vocabulary management (rename, merge, ordering) arrives in D7. Like every
# Move-owned record, Rooms live inside the tenant schema — no organization_id.
class Room < ApplicationRecord
  belongs_to :move
  has_many :boxes, dependent: :nullify

  validates :name, presence: true
  validates :name, uniqueness: { scope: :move_id, case_sensitive: false }
end

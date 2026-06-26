# frozen_string_literal: true

# Source: https://github.com/rails/rails/blob/8-0-stable/activerecord/lib/rails/generators/active_record/model/templates/model.rb.tt
class User < ApplicationRecord
  include Roleable

  # Org memberships live in the shared `public` schema. The FK from
  # organization_memberships has no ON DELETE CASCADE, so without this a
  # `users` DELETE is rejected (PG::ForeignKeyViolation). Account deletion is
  # owned by Accounts::Delete; this is the safety net that keeps user.destroy!
  # from ever 500ing on a dangling membership.
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end

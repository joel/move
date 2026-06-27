# frozen_string_literal: true

# Source: https://github.com/rails/rails/blob/8-0-stable/activerecord/lib/rails/generators/active_record/model/templates/model.rb.tt
class User < ApplicationRecord
  include Roleable

  # Org memberships live in the shared `public` schema (FK without ON DELETE
  # CASCADE). Deleting an account is owned by Accounts::Delete, which removes
  # memberships by destroying the user's solo orgs first. We `restrict` rather
  # than `:destroy` so a raw `user.destroy!` can never silently orphan tenant
  # data — it fails loudly, forcing deletion through the action.
  has_many :organization_memberships, dependent: :restrict_with_error
  has_many :organizations, through: :organization_memberships

  # Versioned legal risk-acknowledgements this account has accepted (#369). The
  # access gate checks for the current version. In `public` (excluded model); the
  # FK's ON DELETE CASCADE is the real cleanup, `delete_all` keeps AR consistent.
  has_many :terms_acceptances, dependent: :delete_all

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end

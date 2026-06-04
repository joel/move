# frozen_string_literal: true

# Source: https://github.com/rails/rails/blob/8-0-stable/activerecord/lib/rails/generators/active_record/model/templates/model.rb.tt
class User < ApplicationRecord
  include Roleable

  has_many :posts, dependent: :destroy
  has_many :organization_memberships, dependent: :destroy
  has_many :organizations, through: :organization_memberships

  validates :email, presence: true, uniqueness: { case_sensitive: false }
end

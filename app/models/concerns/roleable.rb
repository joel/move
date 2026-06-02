# frozen_string_literal: true

module Roleable
  extend ActiveSupport::Concern

  included do
    attribute :roles_mask, :integer, default: -> { default_roles_mask }
  end

  class_methods do
    def roles_config
      Rails.configuration.roles || []
    end

    def default_roles_mask
      guest_index = roles_config.index(:guest)
      guest_index ? (1 << guest_index) : 0
    end
  end

  def roles
    self.class.roles_config.select { |role| role?(role) }
  end

  def roles=(assigned_roles)
    normalized = Array(assigned_roles).map(&:to_sym)
    self.roles_mask = normalized.reduce(0) { |mask, role| mask | role_bit(role) }
  end

  def role?(role)
    roles_mask.to_i.anybits?(role_bit(role.to_sym))
  end

  private

  def role_bit(role)
    index = self.class.roles_config.index(role)
    return 0 unless index

    1 << index
  end
end

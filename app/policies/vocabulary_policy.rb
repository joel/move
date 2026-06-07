# frozen_string_literal: true

# Authorizes management of a Move's controlled vocabularies (categories, tags,
# rooms — D7). The authorized record is the **Move**: viewing the management
# surface is open to any signed-in member, but adding / renaming / removing a
# value is admin-only and only on a writable (non-archived) Move. Roles are
# admin/member today; contributor/viewer arrive in D11.
class VocabularyPolicy < ApplicationPolicy
  # record is the Move whose vocabularies are managed.
  def index?
    user.present?
  end

  def manage?
    user.present? && record.admin?(user) && record.writable?
  end

  alias create? manage?
  alias update? manage?
  alias destroy? manage?
end

# frozen_string_literal: true

# Authorizes management of a Move's controlled vocabularies (categories, tags,
# rooms — D7). The authorized record is the **Move**: viewing the management
# surface is open to any member, but curating a value (add / rename / remove) is
# admin-only and only on a writable (non-archived) Move. Contributors mutate the
# Move's *content* (boxes/items) but do not curate its taxonomy — that is an
# admin concern (D11).
class VocabularyPolicy < ApplicationPolicy
  include MoveMembershipAuthorization

  # record is the Move whose vocabularies are managed. Viewing requires
  # membership — a member of another Move in the same tenant must not see this
  # Move's category/tag/room names.
  def index?
    reader_of?(record)
  end

  def manage?
    admin_of?(record) && record.writable?
  end

  alias create? manage?
  alias update? manage?
  alias destroy? manage?
end

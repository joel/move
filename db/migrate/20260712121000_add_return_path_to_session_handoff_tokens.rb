# frozen_string_literal: true

# D14 (#608): a handoff can carry an optional in-tenant destination — the
# invitation accept flow lands the invitee ON the Move they just joined instead
# of the tenant root. Only a safe internal path is ever honored (the controller
# validates before redirecting); nil keeps the existing root_path behaviour.
class AddReturnPathToSessionHandoffTokens < ActiveRecord::Migration[8.1]
  def change
    add_column :session_handoff_tokens, :return_path, :string, if_not_exists: true
  end
end

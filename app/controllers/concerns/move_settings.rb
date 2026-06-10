# frozen_string_literal: true

# Shared rendering for the F3 Settings/Assistant screen, used by both
# SettingsController (#show) and IntegrationTokensController (#create renders the
# screen inline so the raw token can be revealed once without ever entering the
# session cookie). Keeps the view's data dependencies in one place.
module MoveSettings
  extend ActiveSupport::Concern

  private

  # Build the Settings/Assistant view for @move. +revealed_token+ is the raw
  # token to display exactly once, right after creation (nil otherwise).
  def settings_view(revealed_token: nil)
    manage_tokens = allowed_to?(:manage_integration_tokens?, @move, with: MovePolicy)
    Views::Settings::Show.new(
      move: @move,
      tokens: @move.integration_tokens.includes(:created_by).order(created_at: :desc),
      editable: editable_settings?,
      manage_tokens: manage_tokens,
      # Creating a token is blocked on an archived Move (revoke stays available).
      can_create_tokens: manage_tokens && @move.writable?,
      revealed_token: revealed_token
    )
  end

  # The settings controls are only interactive for a user who could actually
  # change them — an editor on a writable Move. Viewers / archived Moves see the
  # resolved values as read-only, never a control that would 403 on submit.
  def editable_settings?
    @move.writable? && allowed_to?(:edit_settings?, @move, with: MovePolicy)
  end
end

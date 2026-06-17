# frozen_string_literal: true

# F3 — Settings & Assistant. Move-level preferences (measurement units, the
# auto-confirm confidence threshold) plus the Assistant/integrations panel that
# lists MCP tokens. Theme (dark default) is a client-only preference handled by
# the `theme` Stimulus controller, so it has no server write here.
#
# Reads render for any member (viewers see read-only). Each preference write
# goes through its shared action, gated by edit_settings? (editor) and the
# archived read-only guard — mirroring the F2 unit-system toggle. Token
# management lives in IntegrationTokensController (admin-only).
class SettingsController < MoveScopedController
  include MoveSettings

  before_action { Current.nav_section = :menu }

  # GET /moves/:move_id/settings
  def show
    authorize! @move, to: :show?, with: MovePolicy
    render settings_view
  end

  # PATCH /moves/:move_id/settings/unit_system
  def update_unit_system
    write_setting(Moves::SetUnitSystem, unit_system: settings_param(:unit_system)) do |result|
      result.success? ? t(".unit_changed") : t(".unit_invalid")
    end
  end

  # PATCH /moves/:move_id/settings/auto_confirm_threshold
  def update_auto_confirm_threshold
    write_setting(Moves::SetAutoConfirmThreshold, threshold: settings_param(:auto_confirm_threshold)) do |result|
      result.success? ? t(".threshold_changed") : t(".threshold_invalid")
    end
  end

  # PATCH /moves/:move_id/settings/recognition_provider (admin-only — keys are
  # secrets, mirroring integration tokens).
  def update_recognition_provider
    write_setting(
      Moves::SetRecognitionProvider, policy: :manage_recognition_keys?,
                                     provider: settings_param(:recognition_provider),
                                     api_key: settings_param(:api_key), model: settings_param(:model)
    ) do |result|
      if result.success? then t(".changed")
      elsif result.failure == :api_key_required then t(".api_key_required")
      else t(".invalid")
      end
    end
  end

  # PATCH /moves/:move_id/settings/embedding_provider (admin-only — reuses the
  # Move's OpenAI key and bills against it, like the recognition provider).
  def update_embedding_provider
    write_setting(
      Moves::SetEmbeddingProvider, policy: :manage_recognition_keys?,
                                   provider: settings_param(:embedding_provider)
    ) do |result|
      result.success? ? t(".changed") : t(".invalid")
    end
  end

  # DELETE /moves/:move_id/settings/recognition_provider/:provider (admin-only).
  def remove_recognition_key
    write_setting(
      Moves::RemoveRecognitionKey, policy: :manage_recognition_keys?, provider: params[:provider]
    ) do |result|
      result.success? ? t(".key_removed") : t(".invalid")
    end
  end

  private

  # Shared write path: policy-authorized (editor by default), archived-guarded,
  # action-driven, then redirect back to settings with a success/failure flash
  # from the block. Secret-bearing writes pass policy: :manage_recognition_keys?.
  def write_setting(action_class, policy: :edit_settings?, **args)
    authorize! @move, to: policy, with: MovePolicy
    return redirect_to(move_settings_path(@move), alert: t(".read_only")) unless @move.writable?

    result = action_class.new.call(move: @move, actor: current_user, **args)
    flash_key = result.success? ? :notice : :alert
    redirect_to move_settings_path(@move), flash: { flash_key => yield(result) }
  end

  def settings_param(key)
    params.dig(:move, key)
  end
end

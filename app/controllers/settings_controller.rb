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

  # PATCH /moves/:move_id/settings/provider_key (admin-only — keys are secrets,
  # mirroring integration tokens). Sets one vendor's key in the shared AI
  # Capability panel (#242).
  def update_provider_key
    write_setting(
      Moves::SetProviderKey, policy: :manage_recognition_keys?,
                             provider: settings_param(:provider), api_key: settings_param(:api_key)
    ) do |result|
      if result.success? then t(".key_saved")
      elsif result.failure == :api_key_required then t(".api_key_required")
      else t(".invalid")
      end
    end
  end

  # DELETE /moves/:move_id/settings/provider_key/:provider (admin-only).
  def remove_provider_key
    write_setting(
      Moves::RemoveProviderKey, policy: :manage_recognition_keys?, provider: params[:provider]
    ) do |result|
      result.success? ? t(".key_removed") : t(".invalid")
    end
  end

  # PATCH /moves/:move_id/settings/recognition_provider (admin-only). Selector +
  # model only; the key is managed via update_provider_key (#242).
  def update_recognition_provider
    write_setting(
      Moves::SetRecognitionProvider, policy: :manage_recognition_keys?,
                                     provider: settings_param(:recognition_provider),
                                     model: settings_param(:model)
    ) do |result|
      if result.success? then t(".changed")
      elsif result.failure == :api_key_required then t(".api_key_required")
      else t(".invalid")
      end
    end
  end

  # PATCH /moves/:move_id/settings/embedding_provider (admin-only). Responds with a
  # Turbo Stream that replaces only the Semantic Search panel body, so switching the
  # provider updates in place instead of a full-page reload (#247); a plain redirect
  # is the non-Turbo fallback.
  def update_embedding_provider
    authorize! @move, to: :manage_recognition_keys?, with: MovePolicy
    return redirect_to(move_settings_path(@move), alert: t(".read_only")) unless @move.writable?

    result = Moves::SetEmbeddingProvider.new.call(
      move: @move, actor: current_user, provider: settings_param(:embedding_provider)
    )
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          Views::Settings::EmbeddingPanelBody::ID,
          Views::Settings::EmbeddingPanelBody.new(move: @move.reload, manage: true)
        )
      end
      format.html do
        flash_key = result.success? ? :notice : :alert
        message = result.success? ? t(".changed") : t(".invalid")
        redirect_to move_settings_path(@move), flash: { flash_key => message }
      end
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

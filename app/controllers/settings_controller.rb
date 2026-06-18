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
  # Capability panel (#242). Refreshes the AI panels in place (#260) — a key
  # change lights up that vendor's options in BOTH the recognition and search
  # selectors, so all three panels re-render; a redirect is the non-Turbo fallback.
  def update_provider_key
    return unless ai_write_allowed?

    result = Moves::SetProviderKey.new.call(
      move: @move, actor: current_user,
      provider: settings_param(:provider), api_key: settings_param(:api_key)
    )
    respond_ai_update(result) do |r|
      if r.success? then t(".key_saved")
      elsif r.failure == :api_key_required then t(".api_key_required")
      else t(".invalid")
      end
    end
  end

  # DELETE /moves/:move_id/settings/provider_key/:provider (admin-only).
  def remove_provider_key
    return unless ai_write_allowed?

    result = Moves::RemoveProviderKey.new.call(
      move: @move, actor: current_user, provider: params[:provider]
    )
    respond_ai_update(result) { |r| r.success? ? t(".key_removed") : t(".invalid") }
  end

  # PATCH /moves/:move_id/settings/recognition_provider (admin-only). Selector +
  # model only; the key is managed via update_provider_key (#242). In place (#260).
  def update_recognition_provider
    return unless ai_write_allowed?

    result = Moves::SetRecognitionProvider.new.call(
      move: @move, actor: current_user,
      provider: settings_param(:recognition_provider), model: settings_param(:model)
    )
    respond_ai_update(result) do |r|
      if r.success? then t(".changed")
      elsif r.failure == :api_key_required then t(".api_key_required")
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

  # Admin gate + archived read-only guard for the in-place AI writes. Returns true
  # to proceed; on a read-only Move redirects with the action-scoped flash and
  # returns false (a redirect is fine even for a Turbo request — Turbo follows it).
  def ai_write_allowed?
    authorize! @move, to: :manage_recognition_keys?, with: MovePolicy
    return true if @move.writable?

    redirect_to(move_settings_path(@move), alert: t(".read_only"))
    false
  end

  # Turbo Stream: refresh the three interdependent AI panels in place (no reload)
  # AND replace the toast region so success/failure feedback still reaches the user
  # (a blank-key submit must say so, not silently re-render — #260). HTML fallback:
  # redirect to settings with the same flash.
  def respond_ai_update(result)
    flash_key = result.success? ? :notice : :alert
    message = yield(result)
    respond_to do |format|
      format.turbo_stream do
        flash.now[flash_key] = message
        render turbo_stream: ai_panels_stream + [
          turbo_stream.replace(Components::FlashToasts::ID, Components::FlashToasts.new)
        ]
      end
      format.html { redirect_to move_settings_path(@move), flash: { flash_key => message } }
    end
  end

  # Replace all three AI panels (capability keys + recognition selector + search
  # selector body) — keys and selector availability are interdependent, so always
  # re-render the set from the (reloaded) Move to keep them consistent.
  def ai_panels_stream
    @move.reload
    [
      turbo_stream.replace(Views::Settings::AiCapabilityPanel::ID,
                           Views::Settings::AiCapabilityPanel.new(move: @move)),
      turbo_stream.replace(Views::Settings::RecognitionProviderPanel::ID,
                           Views::Settings::RecognitionProviderPanel.new(move: @move, manage: true)),
      turbo_stream.replace(Views::Settings::EmbeddingPanelBody::ID,
                           Views::Settings::EmbeddingPanelBody.new(move: @move, manage: true))
    ]
  end

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

# frozen_string_literal: true

# F3 — Assistant & Integrations: create and revoke per-Move MCP integration
# tokens (Domain §4.13). Admin-only (manage_integration_tokens?). Create renders
# the Settings screen inline with the raw token revealed exactly once — the raw
# value never enters the session cookie or any redirect. Revoke is a soft delete
# (sets revoked_at) so an active MCP client is cut off immediately.
class IntegrationTokensController < MoveScopedController
  include MoveSettings

  before_action :require_token_admin!
  before_action { Current.nav_section = :menu }

  # POST /moves/:move_id/integration_tokens
  def create
    result = MoveIntegrationTokens::Create.new.call(
      move: @move, name: token_param(:name), actor: current_user
    )

    case result
    in Dry::Monads::Success(minted)
      # Shown once: render the settings screen directly with the raw token so it
      # is never persisted in the flash/session. A reload loses it forever.
      flash.now[:notice] = t(".created", name: minted.token.name)
      render settings_view(revealed_token: minted.raw_token)
    in Dry::Monads::Failure(_)
      flash.now[:alert] = t(".create_failed")
      render settings_view, status: :unprocessable_content
    end
  end

  # DELETE /moves/:move_id/integration_tokens/:id
  def destroy
    result = MoveIntegrationTokens::Revoke.new.call(token: token, actor: current_user)

    case result
    in Dry::Monads::Success(_token)
      redirect_to move_settings_path(@move), notice: t(".revoked")
    in Dry::Monads::Failure(_)
      redirect_to move_settings_path(@move), alert: t(".revoke_failed")
    end
  end

  private

  def require_token_admin!
    authorize! @move, to: :manage_integration_tokens?, with: MovePolicy
  end

  def token
    @token ||= @move.integration_tokens.find(params.expect(:id))
  end

  def token_param(key)
    params.dig(:integration_token, key)
  end
end

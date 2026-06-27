# frozen_string_literal: true

# The terms-agreement interstitial (#369). Every authenticated account must
# accept the current terms version before any other tenant surface; the gate on
# TenantController redirects here until they do. This controller IS the gate, so
# it skips `require_terms_agreement!` to avoid a redirect loop — it still requires
# an authenticated user and a resolved tenant (inherited from TenantController).
# Rendered in the plain ApplicationLayout (no app nav): the account is not "in"
# the app yet, so the focused wall must not offer navigation past it.
class AgreementsController < TenantController
  skip_before_action :require_terms_agreement!
  layout -> { Views::Layouts::ApplicationLayout }

  # GET /agreement
  def show
    # Already accepted (e.g. landed here via a stale link)? Don't strand them.
    return redirect_to moves_path if terms_accepted?

    render Views::Agreements::Show.new
  end

  # POST /agreement
  def accept
    result = Terms::Accept.new.call(
      user: current_user,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    case result
    in Dry::Monads::Success(_acceptance)
      # Straight to the app home (not root_path → welcome#home → moves_path):
      # the extra redirect hop would sweep the flash before it is shown.
      redirect_to moves_path, notice: t(".accepted")
    in Dry::Monads::Failure(_)
      redirect_to agreement_path, alert: t(".failed")
    end
  end
end

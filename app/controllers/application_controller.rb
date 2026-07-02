# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include ActionPolicy::Controller

  layout -> { Views::Layouts::ApplicationLayout }

  authorize :user, through: :current_user

  rescue_from ActionPolicy::Unauthorized do
    respond_to do |format|
      format.html do
        render Views::Shared::Forbidden.new, status: :forbidden
      end
      format.any { head :forbidden }
    end
  end

  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user, :current_tenant, :on_apex_host?, :google_credentials_present?

  before_action :set_current_user
  # The terms-agreement gate (#369) is global and fail-closed: every authenticated
  # web surface is gated by default, so a new controller can't silently bypass it.
  # It no-ops for unauthenticated requests, and the auth/session-establishment
  # controllers (Rodauth, handoff, Google, the agreement wall itself) skip it
  # explicitly. ActionController::API controllers (MCP) don't inherit this.
  before_action :require_terms_agreement!

  private

  # Expose the signed-in User to in-request rendering (role-aware nav) via
  # Current, mirroring Current.move/tenant. Reset after each request by
  # ActiveSupport::CurrentAttributes.
  def set_current_user
    Current.user = current_user
    Current.source = :web
  end

  def current_user
    rodauth.rails_account
  end

  # The active Apartment tenant (Organization slug), or nil on the public apex.
  def current_tenant
    tenant = Apartment::Tenant.current
    tenant unless tenant == Apartment.default_tenant || tenant == "public"
  end

  # Whether the signed-in user belongs to the current tenant's Organization.
  # The tenant boundary (TenantController#require_membership!) authorizes on this,
  # so a session that lands on an org subdomain the user is not a member of gets a
  # non-disclosing 404 instead of reaching tenant surfaces. False on the apex/no
  # tenant or when unauthenticated. Indexed `exists?` — no rows loaded into Ruby.
  # Defined here (not on TenantController) so it resolves for the whole controller
  # tree and is a single, stubbable seam.
  def member_of_current_tenant?
    return false if current_user.nil? || current_tenant.nil?

    Organization.member?(user_id: current_user.id, slug: current_tenant)
  end

  # True when the request is on an org subdomain whose tenant SCHEMA was just
  # dropped — used after account/user deletion to fall back to the apex instead
  # of routing back through a now-missing tenant (the elevator would 404).
  # Checks the schema, not the Organization row: teardown drops the schema before
  # destroying the row, so if a partial teardown drops the schema but the row
  # delete fails, the schema is gone while the row lingers — the schema is the
  # signal the elevator actually uses. Unreachable today (a user owns a single
  # org); it guards the multi-solo-org partial-teardown path.
  def current_subdomain_dropped?
    apex_host.present? && current_tenant.present? &&
      !ActiveRecord::Base.connection.schema_exists?(current_tenant)
  end

  # True only on the canonical apex host (the URL host this app generates links
  # for — move-easy.org in prod, move.move-easy.docker in dev). Google
  # OAuth/One Tap derive their callback + FedCM origin from the request host,
  # but only the apex is registered with Google; excluded labels (www, move)
  # also resolve to the public tenant, so a host check — not just
  # current_tenant.nil? — is what keeps Google off non-canonical hosts.
  def on_apex_host?
    apex_host.present? && request.host == apex_host
  end

  # The canonical apex host this app generates links for (move-easy.org in prod,
  # move.move-easy.docker in dev). Single source of truth for on_apex_host?
  # and the session-handoff failure's apex login URL (#280).
  def apex_host
    Rails.application.config.action_mailer.default_url_options&.dig(:host)
  end

  # Both Google credentials are required for the OAuth redirect flow (the code
  # exchange needs the secret). Gates whether any Google sign-in affordance —
  # the apex button or the subdomain "route via apex" link — is offered at all.
  def google_credentials_present?
    ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
  end

  def require_authenticated_user!
    return if current_user

    message = "Please sign in to continue."

    respond_to do |format|
      format.html do
        flash.now[:alert] = message
        render Views::Shared::Unauthorized.new, status: :unauthorized
      end
      format.any { head :unauthorized }
    end
  end

  # The terms-agreement gate (#369): an authenticated account must accept the
  # current terms version before any app surface. No-ops when unauthenticated
  # (login/create-account/the apex are reachable logged-out; each controller's own
  # `require_authenticated_user!` handles auth). Acceptance is identity-level, so
  # the gate holds whatever path (email or Google) created the account.
  def require_terms_agreement!
    return if current_user.nil?
    # Gate only on org subdomains. The app — and the agreement wall itself
    # (AgreementsController < TenantController) — live on tenants; the apex is a
    # pure auth broker (#280) that clears its session on a successful handoff, so
    # an authenticated apex session only lingers in an error/fallback state (#349).
    # Redirecting it to the tenant-only `/agreement` would 404 and strand the user
    # (incl. account management/deletion); the gate re-engages the moment they
    # reach their subdomain.
    return if current_tenant.nil?
    # Logout must stay reachable so an unaccepted account can leave from the wall.
    # Rodauth renders through RodauthController (so this gate DOES run for its
    # views); exempt only the logout path. Login/verify/email-auth render
    # unauthenticated, so they no-op above; passkey-management renders are gated.
    return if request.path == rodauth.logout_path
    return if terms_accepted?

    remember_terms_return_path
    redirect_to agreement_path
  end

  # Single source of truth for "has the account accepted the live terms version".
  # Indexed `exists?` — no rows are loaded into Ruby.
  def terms_accepted?
    current_user.terms_acceptances.exists?(terms_version: Terms::CURRENT_VERSION)
  end

  # Remember where the user was headed so accepting the terms returns them there
  # (UX: don't lose a deep link behind the wall). Only a safe, tenant-local GET
  # path — never a mutation target or an off-host URL, and never the wall itself.
  def remember_terms_return_path
    # Only safe, idempotent navigations (GET/HEAD) — never a POST/PATCH/DELETE
    # target, which we could not legitimately replay as a GET after acceptance.
    return unless safe_navigation_request?
    # Skip paths that themselves redirect onward (root → welcome#home → moves):
    # returning there after accept would bounce once more and sweep the success
    # flash. They are not real deep links anyway — fall back to the app home.
    return if request.path == "/" || request.path.start_with?("/welcome")

    path = request.fullpath
    return unless path.start_with?("/") && !path.start_with?("//")
    return if path.start_with?(agreement_path)

    session[:terms_return_to] = path
  end

  def safe_navigation_request?
    request.get? || request.head?
  end
end

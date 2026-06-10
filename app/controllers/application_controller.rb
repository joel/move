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

  helper_method :current_user, :current_tenant

  before_action :set_current_user

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
end

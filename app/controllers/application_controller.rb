# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include ActionPolicy::Controller
  include Tenancy

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

  # Non-disclosing 404 — covers missing records, cross-org access, and unknown
  # subdomains alike, so none of them leak existence.
  rescue_from ActiveRecord::RecordNotFound do
    respond_to do |format|
      format.html do
        render Views::Shared::NotFound.new, status: :not_found
      end
      format.any { head :not_found }
    end
  end

  # Only allow modern browsers supporting webp images, web push, badges,
  # import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :current_user

  private

  def current_user
    rodauth.rails_account
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

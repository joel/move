# frozen_string_literal: true

# Test-only helper to sign in as a given user without going through the full
# auth flow. Routed only in the test environment (see config/routes.rb).
class TestSessionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  # Establishes the session itself; the terms gate (#369) doesn't apply here.
  skip_before_action :require_terms_agreement!, raise: false

  def show
    raise ActionController::RoutingError, "Not Found" unless Rails.env.test?

    user = find_user
    user.update!(status: rodauth.account_open_status_value)
    session[rodauth.session_key] = user.id
    session[rodauth.authenticated_by_session_key] = ["test"]

    head :ok
  end

  private

  def find_user
    return User.find(params.expect(:user_id)) if params[:user_id].present?
    return User.find_by!(email: params.expect(:email)) if params[:email].present?

    raise ActionController::BadRequest, "Missing user_id or email"
  end
end

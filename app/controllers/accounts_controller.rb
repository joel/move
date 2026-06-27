# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :require_authenticated_user!
  before_action :set_user

  # GET /account
  def show
    render Views::Accounts::Show.new(user: @user)
  end

  # PATCH/PUT /account
  def update
    if @user.update(account_params)
      redirect_to account_path, notice: t(".notice")
    else
      render Views::Accounts::Show.new(user: @user),
             status: :unprocessable_content
    end
  end

  # DELETE /account
  def destroy
    case Accounts::Delete.new.call(user: @user)
    in Dry::Monads::Success(_user_id)
      reset_session
      # Deletion may have dropped the tenant schema for the org subdomain we are
      # on, so a relative redirect would 404 in the elevator — always land the
      # signed-out user on the canonical apex root.
      redirect_to post_deletion_url, allow_other_host: true, notice: t(".notice")
    in Dry::Monads::Failure(:owns_shared_data)
      # Refused before any drop, so the current subdomain is intact.
      redirect_to account_path, alert: t(".shared_data")
    in Dry::Monads::Failure(_)
      # A partial multi-org teardown may have dropped the current subdomain;
      # fall back to the apex so the elevator doesn't 404.
      redirect_to failure_redirect_url, allow_other_host: true, alert: t(".failure")
    end
  end

  private

  def set_user
    @user = current_user
  end

  def post_deletion_url
    apex_host ? root_url(host: apex_host) : root_path
  end

  def failure_redirect_url
    current_subdomain_dropped? ? post_deletion_url : account_path
  end

  def account_params
    params.expect(user: [:name])
  end
end

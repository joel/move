# frozen_string_literal: true

class WelcomeController < ApplicationController
  # Cross-host notices (#844). Sessions are host-only (#280), so a flash set on an
  # org subdomain never reaches the apex. A flow that ends in a cross-host redirect
  # to the apex root instead passes a FIXED key (`/?notice=<key>`); the apex maps
  # it to a localized flash here. Allow-listed keys only, never free text, so the
  # param can't inject a message.
  CROSS_HOST_NOTICES = { "account_deleted" => "accounts.destroy.notice" }.freeze #: Hash[String, String]

  before_action :consume_cross_host_notice, only: :home

  #: () -> untyped
  def home
    # On an Organization subdomain the entry screen is the Move list (A1).
    return redirect_to(moves_path) if current_tenant && current_user

    render Views::Welcome::Home.new
  end

  private

  # One-shot: whatever the key, strip it with a redirect to the clean URL, so a
  # reload or a shared link doesn't replay the toast. Only a signed-out visitor
  # gets the toast — every current key reports an account that no longer exists,
  # so a crafted link can't tell a signed-in user their account was deleted.

  #: () -> void
  def consume_cross_host_notice
    return unless params.key?(:notice)

    key = CROSS_HOST_NOTICES[params[:notice].to_s]
    flash[:notice] = t(key) if key && current_user.nil?
    redirect_to root_path
  end
end

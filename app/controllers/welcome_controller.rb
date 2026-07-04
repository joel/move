# frozen_string_literal: true

class WelcomeController < ApplicationController
  #: () -> untyped
  def home
    # On an Organization subdomain the entry screen is the Move list (A1).
    return redirect_to(moves_path) if current_tenant && current_user

    render Views::Welcome::Home.new
  end
end

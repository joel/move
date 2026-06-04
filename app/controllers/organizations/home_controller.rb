# frozen_string_literal: true

module Organizations
  # Tenant root (org subdomain). PR2 replaces this with the A1 Move selector.
  class HomeController < ApplicationController
    before_action :require_organization_membership!

    # GET / (on <slug>.move.workeverywhere.docker)
    def show
      render Views::Organizations::Home.new(organization: Current.organization)
    end
  end
end

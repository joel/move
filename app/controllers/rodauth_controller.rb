# frozen_string_literal: true

class RodauthController < ApplicationController
  # Used by Rodauth for rendering views, CSRF protection, running callbacks, etc.
  #
  # Skip the terms gate (#369): the auth flows (login, logout, verify, email-auth)
  # render through here, and an authenticated-but-unaccepted account must be able
  # to sign OUT from the agreement wall — gating this would redirect /logout back
  # to the wall, trapping them.
  skip_before_action :require_terms_agreement!, raise: false
end

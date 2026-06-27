# frozen_string_literal: true

class RodauthController < ApplicationController
  # Used by Rodauth for rendering views, CSRF protection, running callbacks, etc.
  #
  # The terms gate (#369) is NOT skipped here: Rodauth renders its views through
  # this controller, so the Rails before_action runs — which is what gates the
  # authenticated passkey-MANAGEMENT renders (`/account/passkeys[/new]`). The gate
  # exempts the logout path (so an unaccepted account can still sign out) and
  # no-ops for the unauthenticated login/verify/email-auth renders. Passkey
  # MUTATIONS (POST) are gated one layer up, in the Roda request, via
  # RodauthMain::AuthMethods#before_webauthn_setup / #before_webauthn_remove (the
  # Rails gate can't catch those — Rodauth mutates before it renders).
end

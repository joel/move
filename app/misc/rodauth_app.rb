# frozen_string_literal: true

class RodauthApp < Rodauth::Rails::App
  unless BuildTasks.assets_precompile?
    configure RodauthMain

    route do |r|
      # Drop a session that references an account which no longer exists
      # (e.g. after a local DB reset, or an account deleted server-side).
      # Left in place, Rodauth clears such a session mid-request inside
      # load_memory and wipes in-flight flow state — notably the
      # verify-account key carried across the two-step verify redirect —
      # bouncing the user to /login with "invalid verify account key".
      # Treating an orphaned session as logged out up front keeps every
      # flow running against a clean, stable session. See issue #32.
      rodauth.clear_session if rodauth.logged_in? && rodauth.account_from_session.nil?

      rodauth.load_memory
      r.rodauth
    end
  end
end

# frozen_string_literal: true

require "sequel/core"

class RodauthMain < Rodauth::Rails::Auth
  unless BuildTasks.assets_precompile?
    configure do # rubocop:disable Metrics/BlockLength
      # ── Features ──────────────────────────────────────────────
      # Passwordless by design: accounts authenticate with passkeys
      # (WebAuthn), one-time email links, or Google, never a password.
      enable :create_account, :verify_account, :login, :logout,
             :email_auth, :webauthn, :webauthn_login, :webauthn_autofill,
             :omniauth, :remember

      db Sequel.postgres(extensions: :activerecord_connection, keep_reference: false)

      # Schema-qualify every Rodauth table to `public`. Rodauth shares the
      # ActiveRecord connection (sequel-activerecord_connection), whose
      # search_path Apartment switches per tenant. These key tables have no AR
      # model, so Apartment clones them (empty) into each tenant schema;
      # qualifying to public ensures auth always reads the real public rows.
      accounts_table Sequel[:public][:users]
      verify_account_table Sequel[:public][:user_verification_keys]
      email_auth_table Sequel[:public][:user_email_auth_keys]
      webauthn_keys_table Sequel[:public][:user_webauthn_keys]
      webauthn_user_ids_table Sequel[:public][:user_webauthn_user_ids]
      webauthn_keys_account_id_column :user_id

      # ── Remember me (persistent sessions) ─────────────────────
      remember_table Sequel[:public][:user_remember_keys]
      remember_deadline_interval({ days: 30 })
      remember_period({ days: 30 })
      extend_remember_deadline? true
      # Host-only remember cookie (#280): like the session cookie, it is NOT shared
      # across subdomains. Remember is set ONLY on the org subdomain (when it
      # consumes a handoff token — see after_login below and
      # SessionHandoffsController), so "stay signed in" works per-domain. The key
      # is rotated (`_remember` -> `_move_remember`) so a browser still holding the
      # old shared `.move-easy.org` remember cookie can't keep authenticating
      # cross-subdomain; the stale cookie is never read and expires on its own.
      remember_cookie_key "_move_remember"
      remember_cookie_options(same_site: :lax)

      # ── OmniAuth (Google social login) ────────────────────────
      # Active only when GOOGLE_CLIENT_ID is configured, so the
      # template runs out of the box without Google credentials.
      omniauth_identities_table Sequel[:public][:user_omniauth_identities]
      omniauth_identities_account_id_column :user_id

      # Register the provider only when BOTH credentials are present: the
      # authorization-code flow can't exchange the code without the secret, so a
      # half-configured provider (id set, secret blank — both are optional in the
      # deploy) would render a button that dead-ends at the callback. One Tap is
      # separate (it verifies the id_token via tokeninfo and needs no secret).
      if ENV["GOOGLE_CLIENT_ID"].present? && ENV["GOOGLE_CLIENT_SECRET"].present?
        omniauth_provider :google_oauth2,
                          ENV.fetch("GOOGLE_CLIENT_ID", nil),
                          ENV.fetch("GOOGLE_CLIENT_SECRET", nil),
                          name: :google,
                          scope: "email,profile"
      end

      # Self-service signup is open, so let Google create accounts too.
      omniauth_create_account? true
      omniauth_verify_account? true

      omniauth_identity_insert_hash do
        super().merge(id: SecureRandom.uuid)
      end

      rails_controller { RodauthController }
      title_instance_variable :@page_title

      account_status_column :status
      login_param "email"
      login_label "Email"
      login_confirm_param "email-confirm"

      # Friendlier copy for the multi-phase (email-first) login flow.
      need_password_notice_flash "Email recognized. Choose how to sign in."
      email_auth_email_sent_notice_flash "A sign-in link has been sent to your email. Check your inbox."
      email_auth_email_sent_redirect { login_path }

      create_account_set_password? false
      verify_account_set_password? false
      require_login_confirmation? false
      require_password_confirmation? false
      require_bcrypt? false

      # Auth-class instance methods live in RodauthMain::AuthMethods (#358) to keep
      # this class small; `super` in them resolves to the Rodauth features as before.
      auth_class_eval { include AuthMethods }

      email_from do
        ENV.fetch("RODAUTH_FROM", ENV.fetch("NOTIF_MAIL_FROM", "no-reply@example.com"))
      end

      create_verify_account_email do
        RodauthMailer.verify_account(self.class.configuration_name, account_id,
                                     verify_account_key_value, carried_invite_token)
      end

      # Pass the request-time tenant (#353): when the sign-in link is requested
      # from an org subdomain, the mailer points the magic link back at THAT
      # subdomain (membership-validated) so login completes there and the #346
      # handoff targets the originating org instead of the primary.
      create_email_auth_email do
        RodauthMailer.email_auth(self.class.configuration_name, account_id,
                                 email_auth_key_value, Apartment::Tenant.current,
                                 carried_invite_token)
      end

      # ── D14 (#608): carry a Move-invitation token through the auth flows ──
      # Rodauth form POSTs drop query params, so every form in the passwordless
      # journey re-emits the token as a hidden field (each view renders its
      # *_additional_form_tags), and both emailed links append it — whichever
      # path the invitee takes, they land back on /invitations/<token>.
      login_additional_form_tags { invite_token_form_tag }
      create_account_additional_form_tags { invite_token_form_tag }
      email_auth_request_additional_form_tags { invite_token_form_tag }
      email_auth_additional_form_tags { invite_token_form_tag }
      verify_account_additional_form_tags { invite_token_form_tag }
      verify_account_resend_additional_form_tags { invite_token_form_tag }

      send_email do |email|
        db.after_commit { email.deliver_later }
      end

      webauthn_origin { ENV.fetch("WEBAUTHN_ORIGIN", base_url) }
      webauthn_rp_id do
        ENV.fetch("WEBAUTHN_RP_ID", webauthn_origin.sub(%r{\Ahttps?://}, "").sub(/:\d+\z/, ""))
      end
      webauthn_rp_name { ENV.fetch("WEBAUTHN_RP_NAME", Rails.application.config.x.brand_name) }
      webauthn_user_verification "preferred"

      # Friendlier, account-scoped URLs (the gem defaults are /webauthn-setup and
      # /webauthn-remove). Multi-segment route values resolve to /account/passkeys
      # and /account/passkeys/new; the *_path helpers update with them, so every
      # link follows. (Rodauth runs ahead of Rails and `resource :account` has no
      # sub-paths, so there's no route conflict.)
      webauthn_remove_route "account/passkeys"
      webauthn_setup_route "account/passkeys/new"
      # Keep passkey management on the management page after adding/removing
      # (the gem default falls through to the post-login redirect → Moves index).
      webauthn_setup_redirect { webauthn_remove_path }
      # Where to land after removing a passkey:
      #   - logged out (removed the credential that authenticated this
      #     passkey-only session → Rodauth cleared it) → the login page;
      #   - passkeys remain → stay on the management page;
      #   - none remain → the account page (manage would bounce to the generic
      #     2FA-setup flow, and its Security card now offers "Add passkey").
      webauthn_remove_redirect do
        next login_path unless logged_in?

        webauthn_setup? ? webauthn_remove_path : "/account"
      end

      # User-facing copy: the Rodauth defaults say "WebAuthn" / "authenticator",
      # which users don't understand — say "passkey" everywhere.
      webauthn_setup_button "Add passkey"
      webauthn_auth_button "Sign in with passkey"
      webauthn_remove_button "Remove passkey"
      webauthn_setup_notice_flash "Passkey added."
      webauthn_remove_notice_flash "Passkey removed."
      webauthn_setup_error_flash "We couldn't add that passkey. Please try again."
      webauthn_auth_error_flash "We couldn't sign you in with that passkey."
      webauthn_not_setup_error_flash "This account doesn't have a passkey yet."
      webauthn_remove_error_flash "We couldn't remove that passkey."
      webauthn_login_error_flash "We couldn't sign you in with your passkey."
      webauthn_invalid_remove_param_message "Select a passkey to remove."
      # Friendlier same-device duplicate handling (InvalidStateError); block form
      # defers the constant load to request time. See app/misc/webauthn/setup_js.rb.
      webauthn_setup_js { Webauthn::SetupJs::SOURCE }

      # ── OmniAuth hooks ────────────────────────────────────────
      omniauth_login_failure_redirect { login_path }

      after_login do
        # NB: no apex remember_login (#280). The apex is a pure auth broker — it
        # clears its own session on handoff (tenant_handoff_url) and never keeps a
        # remember cookie. "Stay signed in" is established on the org subdomain
        # when it consumes the handoff token (SessionHandoffsController).
        next unless authenticated_by&.include?("omniauth")

        # Google (OmniAuth) sign-in bypasses verify_account_view, so an account
        # freshly created by omniauth_create_account? would otherwise land with
        # no Organization and nowhere to create Moves. Provision the personal
        # tenant here (idempotent — guards on member_of_any_organization?). Runs
        # after the account-creation transaction has committed, so the tenant
        # DDL/pg_dump is not nested in a transaction.
        ensure_personal_organization

        # Backfill the user's name from the Google profile on first login.
        next if omniauth_name.blank?

        user = ::User.find_by(id: account_id)
        user&.update!(name: omniauth_name) if user&.name.blank?
      end

      logout_redirect "/"

      # Route authenticated users to their Organization subdomain (the A1 Move
      # list) via a single-use handoff token (#280): cookies are host-only, so
      # the apex session does not travel — the token establishes the subdomain's
      # own session. The target is the org the login started from when applicable
      # (#346, membership-validated). Falls back to the apex when the user has no
      # Organization yet.
      # A carried invite token overrides both post-auth destinations: the user
      # authenticated in order to accept an invitation, so send them back to the
      # apex landing (session INTACT — the accept POST hands off from there).
      # Invited signups also skip personal-org provisioning (AuthMethods), so
      # @onboarding_slug stays nil and this branch is what routes them.
      login_redirect do
        if (invite = carried_invite_token)
          "/invitations/#{invite}"
        else
          (slug = handoff_target_slug) ? tenant_handoff_url(slug) : "/"
        end
      end
      verify_account_redirect do
        @onboarding_slug ? tenant_handoff_url(@onboarding_slug) : login_redirect
      end
    end
  end
end

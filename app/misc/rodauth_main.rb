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
      # Share the remember cookie across org subdomains (same zone as the
      # session cookie), so persistent login survives the apex -> subdomain hop.
      remember_cookie_options(
        **{ same_site: :lax, domain: Rails.application.config.x.cookie_domain }.compact
      )

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

      auth_class_eval do # rubocop:disable Metrics/BlockLength
        # No second factor is wired up; keeps the :webauthn feature from
        # treating passkeys as a 2FA step.
        def two_factor_authentication_setup?
          false
        end

        def get_password_hash
          nil
        end

        # Name a newly registered passkey: prefer the name the user typed,
        # else resolve it from the authenticator's AAGUID, else guess from
        # the User-Agent. See app/misc/webauthn/*.
        def webauthn_key_insert_hash(webauthn_credential)
          super.merge(name: resolve_passkey_name(webauthn_credential))
        end

        def resolve_passkey_name(webauthn_credential)
          submitted = param_or_nil("passkey_name").to_s.strip
          base = if submitted.present?
                   submitted[0, 80]
                 else
                   aaguid = extract_aaguid(webauthn_credential)
                   Webauthn::AaguidLookup.lookup(aaguid) ||
                     Webauthn::NameSuggester.from_user_agent(request.user_agent)
                 end
          unique_passkey_name(base)
        end

        # Keep names distinct per account so the manage-passkeys list never shows
        # two identical labels (e.g. two "Linux device" from the same User-Agent).
        # Appends " 2", " 3", … to the first collision; trims to the 80-char column.
        def unique_passkey_name(base)
          existing = webauthn_keys_ds.select_map(:name).compact
          return base unless existing.include?(base)

          stem = base[0, 76]
          n = 2
          n += 1 while existing.include?("#{stem} #{n}")
          "#{stem} #{n}"
        end

        # Allow adding another passkey even when one is already registered, by
        # dropping ONLY the creation-time `excludeCredentials` list. Rodauth's
        # default feeds every stored credential id into `excludeCredentials`;
        # because platform passkeys (Google/iCloud) sync across a user's devices,
        # the existing credential is present everywhere, so the authenticator
        # refuses to create another (InvalidStateError) and the user can never
        # add a second passkey. excludeCredentials is only a dedup hint, not a
        # security control.
        #
        # We override `new_webauthn_credential` (creation) rather than
        # `account_webauthn_ids`, because that method ALSO builds `allowCredentials`
        # for passkey sign-in (`webauthn_allow`) — blanking it would break
        # authentication for non-discoverable credentials (#268 / Codex P1). This
        # mirrors the gem's implementation with `:exclude` forced empty.
        def new_webauthn_credential
          WebAuthn::Credential.options_for_create(
            timeout: webauthn_setup_timeout,
            user: { id: account_webauthn_user_id, name: webauthn_user_name },
            authenticator_selection: webauthn_authenticator_selection,
            attestation: webauthn_attestation,
            extensions: webauthn_extensions,
            exclude: [],
            **webauthn_create_relying_party_opts
          )
        end

        def extract_aaguid(webauthn_credential)
          webauthn_credential
            .response
            .authenticator_data
            .attested_credential_data
            &.aaguid
        rescue StandardError # rubocop:disable Move/BroadRescue -- optional aaguid from untrusted data → nil
          nil
        end

        def before_create_account
          super
          set_account_id_and_timestamps
        end

        # rodauth-omniauth creates the account through its OWN path
        # (omniauth_create_account -> omniauth_save_account), which does NOT call
        # before_create_account, so the id/timestamp defaults set there are
        # skipped. public.users.created_at/updated_at are NOT NULL with no DB
        # default, so without this the first Google sign-up's account INSERT
        # fails (500) before after_login is ever reached. Fill them on the
        # OmniAuth create path too. (id has a gen_random_uuid() default, but we
        # set it for parity with the standard path.)
        def before_omniauth_create_account
          super
          set_account_id_and_timestamps
        end

        def set_account_id_and_timestamps
          account[:id] ||= SecureRandom.uuid
          timestamp = Time.current
          account[:created_at] ||= timestamp
          account[:updated_at] ||= timestamp
        end

        # Verify accounts without forcing a password step (we are
        # passwordless), then auto-login and respond.
        def verify_account_view
          return super if verify_account_set_password? || !account

          transaction do
            before_verify_account
            verify_account
            clear_tokens(:verify_account)
            after_verify_account
          end

          autologin_session("verify_account") if verify_account_autologin?
          remove_session_value(verify_account_session_key)
          # Provision the personal tenant AFTER the verify transaction commits —
          # tenant creation runs DDL/pg_dump and must not nest in that transaction.
          ensure_personal_organization
          verify_account_response
        end

        # ── Tenant onboarding ─────────────────────────────────────
        # Every verified account gets a personal Organization (an Apartment
        # tenant) so it has somewhere to create Moves. Idempotent; sets
        # @onboarding_slug for the post-verify redirect.
        def ensure_personal_organization
          return if member_of_any_organization?

          user = ::User.find(account_id)
          result = Organizations::Create.new.call(
            name: organization_name_for(user),
            slug: generate_tenant_slug(user),
            owner: user
          )

          if result.success?
            @onboarding_slug = result.value!.slug
          else
            # Never strand a verified user without surfacing why.
            Rails.logger.error(
              "[onboarding] could not create org for account #{account_id}: #{result.failure.inspect}"
            )
          end
        end

        def member_of_any_organization?
          OrganizationMembership.exists?(user_id: account_id)
        end

        def primary_organization
          Organization
            .joins(:organization_memberships)
            .find_by(organization_memberships: { user_id: account_id })
        end

        def tenant_home_url(slug)
          "https://#{slug}.#{Rails.application.config.x.tenant_zone}/"
        end

        def organization_name_for(user)
          base = user.name.presence || user.email.to_s.split("@").first
          "#{base}'s Move"
        end

        # Build a unique, DNS-label/schema-safe slug from the user's name/email.
        def generate_tenant_slug(user)
          seed = user.name.presence || user.email.to_s.split("@").first
          base = seed.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
          base = "org-#{base}" unless base.match?(/\A[a-z]/)
          base = (base.presence || "org")[0, 50]
          candidate = base
          suffix = 1
          while slug_unavailable?(candidate)
            candidate = "#{base}-#{suffix}"
            suffix += 1
          end
          candidate
        end

        # A slug is unavailable if it's already taken OR a reserved subdomain;
        # otherwise a user like admin@… would derive the reserved slug "admin",
        # which Organizations::Create rejects, leaving them without a tenant.
        def slug_unavailable?(slug)
          Organizations::Create::RESERVED_SLUGS.include?(slug) ||
            Organization.exists?(slug: slug)
        end
      end

      email_from do
        ENV.fetch("RODAUTH_FROM", ENV.fetch("NOTIF_MAIL_FROM", "no-reply@example.com"))
      end

      create_verify_account_email do
        RodauthMailer.verify_account(self.class.configuration_name, account_id, verify_account_key_value)
      end

      create_email_auth_email do
        RodauthMailer.email_auth(self.class.configuration_name, account_id, email_auth_key_value)
      end

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
        remember_login

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

      # Route authenticated users to their Organization subdomain (the A1
      # Move list). Apex login UI -> tenant home; the shared cookie keeps the
      # session. Falls back to the apex when the user has no Organization yet.
      login_redirect do
        (org = primary_organization) ? tenant_home_url(org.slug) : "/"
      end
      verify_account_redirect do
        @onboarding_slug ? tenant_home_url(@onboarding_slug) : login_redirect
      end
    end
  end
end

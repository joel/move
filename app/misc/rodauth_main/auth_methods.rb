# frozen_string_literal: true

class RodauthMain < Rodauth::Rails::Auth
  # Instance methods for the Rodauth auth class, extracted from the configure
  # block's `auth_class_eval` (#358) to keep RodauthMain readable and under the
  # class-length budget. Included via `auth_class_eval { include AuthMethods }`.
  # `super` here resolves to the Rodauth feature implementations exactly as when
  # these were defined inline (the module sits just above the feature ancestors).
  module AuthMethods # rubocop:disable Metrics/ModuleLength
    # No second factor is wired up; keeps the :webauthn feature from
    # treating passkeys as a 2FA step.
    def two_factor_authentication_setup?
      false
    end

    # rubocop:disable Naming/AccessorMethodName -- get_password_hash is a Rodauth API method name
    def get_password_hash
      nil
    end
    # rubocop:enable Naming/AccessorMethodName

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

    # Terms-agreement gate for passkey MANAGEMENT (#369). Rodauth routes are
    # served by the Roda middleware, so they bypass the Rails before_action gate
    # (ApplicationController#require_terms_agreement!) entirely — which is why
    # logout stays reachable from the wall, but also why these authenticated
    # account-management routes (`/account/passkeys`, `/account/passkeys/new`)
    # would otherwise let an unaccepted account add/remove passkeys. Enforce
    # acceptance here, at the Rodauth layer. Login-side webauthn routes
    # (webauthn_login/_auth) are pre-auth and intentionally NOT gated.
    def before_webauthn_setup
      super
      require_terms_agreement_for_management
    end

    def before_webauthn_remove
      super
      require_terms_agreement_for_management
    end

    # Redirect an unaccepted account to the agreement wall. Tenant-only: the wall
    # lives on the org subdomain and the apex is a broker (mirrors the Rails gate's
    # current_tenant guard), so never redirect to the tenant-only wall off-tenant.
    def require_terms_agreement_for_management
      return if Apartment::Tenant.current == "public"
      return if TermsAcceptance.exists?(user_id: account_id, terms_version: Terms::CURRENT_VERSION)

      request.redirect("/agreement")
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

    # ── D14 (#608): Move-invitation token carry ───────────────
    # The invite token rides the auth flows as a request param (hidden form
    # fields + emailed links). Charset-validated before ANY use — it is echoed
    # into HTML and URLs, so only the raw-token shape ever passes through.
    #
    # The session stash below bridges ONE hop: Rodauth's GET-with-key handlers
    # (verify-account, email-auth) stash the key in the session and redirect to
    # a clean URL, dropping our query param — so the re-rendered form would
    # lose the carry. Param always wins; the stash dies with the session wipe
    # at login (login_session/clear_session), so it can never go stale into a
    # later unrelated sign-in.
    # Memoized onto the instance because the login machinery WIPES both other
    # carriers mid-request: autologin/login_session calls clear_session (killing
    # the stash) before login_redirect / ensure_personal_organization run. The
    # positive value is pinned at route entry (before_*_route below), so those
    # late hooks still see it.
    def carried_invite_token
      return @carried_invite_token if defined?(@carried_invite_token) && @carried_invite_token

      token = param_or_nil("invite_token") || session[:invite_token]
      token = nil unless token.is_a?(String) && token.match?(MoveInvitation::TOKEN_FORMAT)
      @carried_invite_token = token
    end

    def stash_invite_token
      token = param_or_nil("invite_token")
      session[:invite_token] = token if token&.match?(MoveInvitation::TOKEN_FORMAT)
    end

    def before_verify_account_route
      carried_invite_token # pin before the auto-verify path clears the session
      stash_invite_token
      super
    end

    def before_email_auth_route
      carried_invite_token
      stash_invite_token
      super
    end

    # The hidden field every auth form re-emits (each view already renders its
    # *_additional_form_tags). Empty string when no valid token is carried.
    def invite_token_form_tag
      token = carried_invite_token
      return "" unless token

      "<input type=\"hidden\" name=\"invite_token\" value=\"#{token}\">"
    end

    # An invited signup should not get a stray personal Organization — they
    # authenticated to join someone else's. Only a live invitation bound to
    # THIS account's email suppresses provisioning; anything else (stale token,
    # someone else's invite) falls back to the normal personal org.
    def invited_signup?
      token = carried_invite_token
      return false unless token

      invitation = MoveInvitation.find_by(token_digest: MoveInvitation.digest(token))
      return false if invitation.nil? || !invitation.pending?

      invitation.email.to_s.casecmp?(::User.find_by(id: account_id)&.email.to_s) || false
    end

    # ── Tenant onboarding ─────────────────────────────────────
    # Every verified account gets a personal Organization (an Apartment
    # tenant) so it has somewhere to create Moves. Idempotent; sets
    # @onboarding_slug for the post-verify redirect. Invited signups skip it
    # (D14) — the accept flow creates their OrganizationMembership instead.
    def ensure_personal_organization
      return if member_of_any_organization?
      return if invited_signup?

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
      Organization.primary_for(account_id)
    end

    # Where to land after auth (#280/#346): the org the login started from
    # (subdomain tenant, or the Google-bridge `org` param) when the account is
    # a member, else the primary org. Logic lives in the resolver service.
    def handoff_target_slug
      SessionHandoffs::TargetResolver.new(
        account_id: account_id,
        current_tenant: Apartment::Tenant.current,
        omniauth_org: omniauth_params&.dig("org"),
        primary_slug: primary_organization&.slug
      ).call
    end

    def tenant_home_url(slug)
      "https://#{slug}.#{Rails.application.config.x.tenant_zone}/"
    end

    # Post-auth landing on the org subdomain. Cookies are host-only (#280),
    # so the apex session does NOT carry to <slug>.<zone>; mint a single-use
    # handoff token bound to (this account, target tenant) and carry it in the
    # URL for the subdomain to exchange for its own host-only session. The raw
    # token is url-safe base64, so it needs no escaping. Falls back to the
    # bare tenant home if minting fails (the user re-authenticates).
    def tenant_handoff_url(slug)
      # find_by (not find!) so a deleted/absent account never raises out of
      # the login_redirect block into a 500.
      user = ::User.find_by(id: account_id)
      raw = user && SessionHandoffs::Mint.new.call(user:, organization_slug: slug).value_or(nil)
      # Couldn't mint a token (no account, or a DB error on the token row):
      # stay on the apex with the session INTACT (don't clear_session below),
      # rather than redirecting the user — unauthenticated — to the tenant home
      # where they'd hit a 401/redirect loop. The broker only clears + hands off
      # on success, so the failure path stays coherent (#349).
      return "/" unless raw

      # The apex is a pure auth broker (#280): once it has handed the session
      # to the subdomain via the token, it must NOT keep a parallel apex login.
      # Host-only cookies mean a later subdomain sign-out can't reach an apex
      # session, so a lingering one would let the user silently re-enter — a
      # logout regression. Clear it here; the subdomain establishes (and
      # remembers) its own session when it consumes the token.
      clear_session
      "#{tenant_home_url(slug)}session/handoff?token=#{raw}"
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
end

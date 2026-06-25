# frozen_string_literal: true

module SessionHandoffs
  # Decides which org subdomain a post-auth handoff (#280) should target (#346).
  #
  # Prefer the org the login STARTED from — the active Apartment tenant on a
  # subdomain login, or the `org` slug carried through the Google apex bridge
  # (omniauth.params) — but ONLY when the account is a member of it; otherwise fall
  # back to the account's primary org. Membership validation is the security guard:
  # a stray/forged origin slug simply falls through to the primary org.
  #
  # A pure query (no side effects), extracted from the Rodauth config so it is
  # unit-testable on its own. `Organization`/`OrganizationMembership` are
  # public-schema (Apartment-excluded) models, so this resolves correctly whether
  # invoked on the apex or a subdomain.
  class TargetResolver
    # @param current_tenant [String, nil] Apartment::Tenant.current at login time
    #   ("public"/nil on the apex; the org slug on a subdomain login)
    # @param omniauth_org [String, nil] the `org` slug forwarded via omniauth.params
    # @param primary_slug [String, nil] the account's primary org slug (fallback)
    def initialize(account_id:, current_tenant:, omniauth_org:, primary_slug:)
      @account_id = account_id
      @current_tenant = current_tenant
      @omniauth_org = omniauth_org
      @primary_slug = primary_slug
    end

    def call
      origin = originating_slug
      return origin if origin.present? && member_of?(origin)

      @primary_slug
    end

    private

    def originating_slug
      return @current_tenant if @current_tenant.present? && !apex_tenant?

      @omniauth_org.presence
    end

    # The apex has no originating org. Match ApplicationController#current_tenant:
    # both "public" and the (configurable) Apartment default tenant are the apex.
    def apex_tenant?
      @current_tenant == "public" || @current_tenant == Apartment.default_tenant
    end

    def member_of?(slug)
      Organization.member?(user_id: @account_id, slug: slug)
    end
  end
end

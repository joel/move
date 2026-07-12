# frozen_string_literal: true

class RodauthMailer < ApplicationMailer
  default to: -> { @rodauth.email_to }, from: -> { @rodauth.email_from }

  def verify_account(name, account_id, key, invite_token = nil)
    @rodauth = rodauth(name, account_id) { @verify_account_key_value = key }
    @account = @rodauth.rails_account
    @email_link = with_invite_token(@rodauth.verify_account_email_link, invite_token)

    mail subject: @rodauth.email_subject_prefix + @rodauth.verify_account_email_subject
  end

  def email_auth(name, account_id, key, tenant = nil, invite_token = nil)
    host = subdomain_host(account_id, tenant)
    @rodauth = rodauth(name, account_id) do
      @email_auth_key_value = key
      # Point the magic link at the originating subdomain so login completes there
      # and the post-auth handoff targets that org (#353/#346). The instance has no
      # request (mail is built in the delivery job), so email_auth_email_link's host
      # comes from rails_url_options — overriding it here redirects the link.
      rails_url_options.merge!(host: host, protocol: "https") if host
    end
    @account = @rodauth.rails_account
    @email_link = with_invite_token(@rodauth.email_auth_email_link, invite_token)

    mail subject: @rodauth.email_subject_prefix + @rodauth.email_auth_email_subject
  end

  private

  # D14 (#608): the emailed auth link re-carries a Move-invitation token so the
  # flow survives a device/browser change (the pre-auth session does not). The
  # links already carry ?key=..., hence the &. Charset-guarded — the token is
  # interpolated into a URL.

  #: (untyped link, untyped invite_token) -> String
  def with_invite_token(link, invite_token)
    return link.to_s unless invite_token&.match?(MoveInvitation::TOKEN_FORMAT)

    "#{link}&invite_token=#{invite_token}"
  end

  # The org-subdomain host to point a sign-in link at — only when `tenant` is a real
  # org the account belongs to (#353). On the apex (no tenant) or for a non-member,
  # returns nil so the link keeps the default apex host (→ primary org). Runs in the
  # delivery job (no request), so it reads the public-schema Organization model.
  def subdomain_host(account_id, tenant)
    return if tenant.blank? || tenant == "public" || tenant == Apartment.default_tenant
    return unless Organization.member?(user_id: account_id, slug: tenant)

    "#{tenant}.#{Rails.application.config.x.tenant_zone}"
  end

  # Default URL options are inherited from Action Mailer, but you can override them
  # ad-hoc by modifying the `rodauth.rails_url_options` hash.
  def rodauth(name, account_id, &block)
    instance = RodauthApp.rodauth(name).allocate
    instance.account_from_id(account_id)
    instance.instance_eval(&block) if block
    instance
  end
end

# frozen_string_literal: true

# Maps request hosts to Organization slugs for subdomain tenancy.
#
# Apex (`move.workeverywhere.docker`) → no tenant (auth/onboarding).
# Org subdomain (`<slug>.workeverywhere.docker`) → that slug.
# Anything else (deeper host, apex label, platform subdomain) → nil.
module TenantHost
  module_function

  def apex_host
    Rails.configuration.x.app_host
  end

  def tenant_domain
    Rails.configuration.x.tenant_domain
  end

  # The org slug for a host, or nil when the host is not an org subdomain.
  def slug_for(host)
    host = host.to_s.downcase
    return nil if host == apex_host

    suffix = ".#{tenant_domain}"
    return nil unless host.end_with?(suffix)

    label = host.delete_suffix(suffix)
    return nil if label.blank? || label.include?(".")
    return nil if "#{label}.#{tenant_domain}" == apex_host # the apex's own label

    label
  end

  def tenant?(host)
    slug_for(host).present?
  end

  # Absolute root URL on an Organization's subdomain.
  def org_root_url(slug, protocol:, port: "")
    "#{protocol}#{slug}.#{tenant_domain}#{port}/"
  end
end

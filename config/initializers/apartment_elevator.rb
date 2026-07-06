# frozen_string_literal: true

require "apartment/elevators/generic"

# Resolves the Apartment tenant from the request host: `<slug>.<tenant_zone>`
# switches to tenant `<slug>`; the apex (`move.<zone>`) and sibling service
# subdomains stay on the public schema.
#
# A custom elevator (rather than Apartment's Subdomain elevator) is required
# because the dev TLS zone `.docker` is not a public suffix, which the
# PublicSuffix-based Subdomain elevator rejects — it would never extract the
# subdomain in development.
class MoveTenantElevator < Apartment::Elevators::Generic
  # `media` is the Cloudflare-edge image-transform Worker host (media.<zone>, #572):
  # a Worker Custom Domain served entirely at Cloudflare's edge, so it never reaches
  # Rails. Excluded defensively so it can never resolve as a tenant if a request
  # ever fell through to the origin.
  EXCLUDED_SUBDOMAINS = %w[move mail storage bucket www media].freeze

  # An unknown tenant subdomain must not disclose existence — return 404.
  def call(env)
    super
  rescue Apartment::TenantNotFound
    [404, { "content-type" => "text/plain; charset=utf-8" }, ["Not found"]]
  end

  def parse_tenant_name(request)
    zone = Rails.application.config.x.tenant_zone.to_s
    host = request.host.to_s.downcase
    return nil if zone.empty? || !host.end_with?(".#{zone}")

    label = host.delete_suffix(".#{zone}")
    return nil if label.empty? || label.include?(".")
    return nil if EXCLUDED_SUBDOMAINS.include?(label)

    label
  end
end

Rails.application.config.middleware.use MoveTenantElevator

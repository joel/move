# frozen_string_literal: true

# pack_public: true -- public API of packs/captures: builds the display URL for a
# Media's image. In production this is a signed Cloudflare-edge transform URL
# (a Worker bound to the R2 bucket resizes on demand, CDN-cached); in dev/test —
# where no Cloudflare front-end exists — it falls back to the proxied master
# (#572 PR1). Kept in its layer (not app/public — neither a persistence contract
# nor a Dry::Monads action); the sigil exposes it past enforce_privacy. See
# packwerk-boundaries.md.

require "openssl"

module MediaVariants
  # Replaces the in-app Active Storage variant pipeline
  # (`media.image.variant(:thumb|:detail)` + rails_storage_proxy_path) at every
  # display surface. The master (≤2048px stripped JPEG, ImageNormalizer) stays the
  # only stored object; display sizes are produced at Cloudflare's edge.
  #
  # URL shape (prod): https://<host>/<size>/<blob_key>?t=<hmac>&exp=<unix>
  #   - <size>     one of SIZES (thumb|detail) — the Worker maps it to width/height
  #   - <blob_key> the Active Storage blob key == the R2 object key (no prefix)
  #   - t          hex HMAC-SHA256 of "<blob_key>|<size>|<exp>" under a DEDICATED
  #                secret (MEDIA_TRANSFORM_SECRET — never secret_key_base)
  #   - exp        unix expiry; the Worker rejects a past exp AND a bad HMAC
  #
  # The token is stateless (no DB row) because the Worker — a separate JS runtime
  # with no Postgres — verifies it independently via Web Crypto. Isolation still
  # rests on the blob key being unguessable and only ever rendered to an
  # authorized in-tenant member; the improvement over the old (never-expiring)
  # Active Storage signed id is the real `exp` — a leaked URL dies within the hour
  # (doc/project/security-model.md, accepted risk F5).
  class TransformUrl
    # The Worker carries its OWN hardcoded copy of this map (it trusts the `size`
    # path segment only once the HMAC verifies), so the two must agree. fit
    # "scale-down" mirrors Media#image's `resize_to_limit:[N,N]` exactly: bounded
    # on both axes, never upscaled, NEVER cropped — the square thumbnail look is
    # the <img class="object-cover"> CSS, not a server crop. Keep in sync with
    # MediaVariants::Prewarm::VARIANTS (asserted by spec).
    SIZES = {
      thumb: { width: 400, height: 400, fit: "scale-down" },
      detail: { width: 1600, height: 1600, fit: "scale-down" }
    }.freeze

    # Long enough to outlive a page's lazy-loaded images and an opened lightbox;
    # short enough that a copied/leaked URL goes dead within the hour. Tokens are
    # freshly minted on every server render, so normal browsing never hits expiry.
    DEFAULT_TTL = 1.hour

    #: (untyped media, Symbol size, ?ttl: ActiveSupport::Duration) -> String?
    def self.for(media, size, ttl: DEFAULT_TTL) = new(media, size, ttl:).call

    #: (untyped media, Symbol size, ttl: ActiveSupport::Duration) -> void
    def initialize(media, size, ttl:)
      @media = media
      @size = size.to_sym
      @ttl = ttl
    end

    # Returns nil when the media has no displayable image (every call site already
    # guards on `image_displayable?`); raises only for a genuinely unknown size,
    # which is a programmer error, not a data condition.

    #: () -> String?
    def call
      return unless @media&.image_displayable?

      raise ArgumentError, "unknown transform size #{@size.inspect}" unless SIZES.key?(@size)

      host.present? ? worker_url : master_proxy_url
    end

    private

    #: () -> String?
    def host = Rails.application.config.x.media_transform_host.presence

    #: () -> String
    def worker_url
      exp = @ttl.from_now.to_i
      "https://#{host}/#{@size}/#{blob_key}?t=#{sign(blob_key, @size, exp)}&exp=#{exp}"
    end

    #: () -> String
    def blob_key = @media.image.blob.key

    # Dev/test fallback: no Cloudflare in front locally, so serve the already
    # ≤2048px-JPEG master straight through Active Storage's own proxy. A plain
    # Ruby service can't call `view_context.rails_storage_proxy_path` (which
    # inherits the request host), so the helper comes off the application's
    # url_helpers with `only_path` — a same-origin relative URL, exactly what the
    # <img src> needs and host-independent.

    #: () -> String
    def master_proxy_url
      Rails.application.routes.url_helpers.rails_storage_proxy_path(@media.image, only_path: true)
    end

    #: (String key, Symbol size, Integer exp) -> String
    def sign(key, size, exp)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{key}|#{size}|#{exp}")
    end

    # Fail loud rather than mint an unsigned URL: reaching here means a host IS
    # configured (prod), so a missing secret is a misconfiguration to surface.

    #: () -> String
    def secret
      Rails.application.config.x.media_transform_secret.presence ||
        raise("MEDIA_TRANSFORM_SECRET is not configured but MEDIA_TRANSFORM_HOST is set")
    end
  end
end

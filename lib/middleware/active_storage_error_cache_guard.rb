# frozen_string_literal: true

# Active Storage's proxy controllers wrap the response in `http_cache_forever`
# (`Cache-Control: public, max-age=<100y>, immutable`) *before* streaming the
# blob. When the variant/file is missing the response ends up non-2xx but still
# carrying that immutable header, so Cloudflare (and browsers) cache the ERROR
# for its full TTL — a transient missing variant then serves a broken image for
# hours after the file is restored (#490, seen live: a 404 pinned at the edge for
# ~6h with `cf-cache-status: HIT` while the origin served the correct image).
#
# This middleware forces any error (>= 400) response under the Active Storage
# routes prefix to be uncacheable, so an error can never get pinned at the edge.
# Successful (2xx) and conditional (3xx, incl. 304) responses are left untouched —
# a real variant stays immutable-cached exactly as before.
#
# Lives in lib/ (ignored by the autoloader, see config/application.rb) and is
# required by config/initializers/active_storage_error_cache_guard.rb.
class ActiveStorageErrorCacheGuard
  DEFAULT_PREFIX = "/rails/active_storage"
  # Caching-related headers stripped from an error response so nothing downstream
  # (browser or CDN) treats it as fresh/immutable.
  STRIPPED = %w[cache-control expires etag last-modified pragma age].freeze

  # `prefix` comes from `config.active_storage.routes_prefix` (passed by the
  # initializer) so the guard tracks a customised mount instead of silently
  # ceasing to match — #490 would otherwise quietly return.
  def initialize(app, prefix: DEFAULT_PREFIX)
    @app = app
    prefix = DEFAULT_PREFIX if prefix.to_s.empty?
    @prefix = prefix.end_with?("/") ? prefix : "#{prefix}/"
  end

  def call(env)
    status, headers, body = @app.call(env)
    make_uncacheable(headers) if error_under_active_storage?(env, status)
    [status, headers, body]
  end

  private

  def error_under_active_storage?(env, status)
    status.to_i >= 400 && env["PATH_INFO"].to_s.start_with?(@prefix)
  end

  def make_uncacheable(headers)
    # delete_if is mutation-safe; downcase the key so it works whether the server
    # emitted Rack 3 lowercase headers or a legacy mixed-case set.
    headers.delete_if { |key, _value| STRIPPED.include?(key.downcase) }
    headers["cache-control"] = "no-store"
  end
end

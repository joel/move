# frozen_string_literal: true

# Register ActiveStorageErrorCacheGuard just outside exception rendering, so it
# sees the FINAL status of an Active Storage proxy request — whether the 404 was
# rescued inside the controller or rendered by ShowExceptions — and can strip the
# immutable cache header AS left on the error before a CDN/browser caches it (#490).
#
# The middleware lives in lib/ (ignored by the autoloader), so require it before
# referencing the constant. This initializer runs before the middleware stack is
# built, so the insert takes effect.
require_relative "../../lib/middleware/active_storage_error_cache_guard"

# Pass the prefix POSITIONALLY — Rails builds middleware with `klass.new(app,
# *args)`, so a keyword here would not reach the constructor as a keyword.
Rails.application.config.middleware.insert_before(
  ActionDispatch::ShowExceptions, ActiveStorageErrorCacheGuard,
  Rails.application.config.active_storage.routes_prefix
)

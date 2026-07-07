# frozen_string_literal: true

# Cloudflare-edge media transform (#572 PR1). MEDIA_TRANSFORM_HOST/_SECRET are
# ENV-provisioned in production (Doppler, like R2_*) and deliberately ABSENT in
# dev/test — no Cloudflare Worker fronts local/CI, so MediaVariants::TransformUrl
# falls back to serving the master directly. Exposed via config.x (not read
# straight from ENV) because two independent consumers need them:
# MediaVariants::TransformUrl (minting) and content_security_policy.rb (img-src).
Rails.application.config.x.media_transform_host = ENV.fetch("MEDIA_TRANSFORM_HOST", nil)
Rails.application.config.x.media_transform_secret = ENV.fetch("MEDIA_TRANSFORM_SECRET", nil)

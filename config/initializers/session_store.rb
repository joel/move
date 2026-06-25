# frozen_string_literal: true

# Host-only session cookie (#280). The cookie is scoped to the exact host that
# set it, so the apex (move-easy.org) and each org subdomain (<slug>.move-easy.org)
# hold SEPARATE sessions — no shared `.move-easy.org` cookie. Crossing from the
# apex to a subdomain after login goes through the single-use handoff token
# (SessionHandoffsController), never a shared cookie.
Rails.application.config.session_store :cookie_store, key: "_move_session"

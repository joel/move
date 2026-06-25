# frozen_string_literal: true

# Host-only session cookie (#280). The cookie is scoped to the exact host that
# set it, so the apex (move-easy.org) and each org subdomain (<slug>.move-easy.org)
# hold SEPARATE sessions — no shared `.move-easy.org` cookie. Crossing from the
# apex to a subdomain after login goes through the single-use handoff token
# (SessionHandoffsController), never a shared cookie.
#
# The key is rotated (`_move_session` -> `_move_session_v2`) as part of the
# cutover: a browser still holding the OLD shared `_move_session` cookie (scoped
# to `.move-easy.org`) would otherwise keep authenticating cross-subdomain, since
# dropping `domain:` only affects future Set-Cookie. Reading a new key makes the
# stale shared cookie inert (it expires on its own), forcing a clean re-login onto
# the host-only model.
Rails.application.config.session_store :cookie_store, key: "_move_session_v2"

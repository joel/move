# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
# Active Storage Direct Upload to R2 (#572) — the ESM build ships with the
# activestorage gem (on the engine's asset load path). Imported dynamically by
# capture_upload_controller.js only when direct upload is enabled (prod). NB: like
# any importmap pin, it is invisible in dev until `bin/rails assets:precompile`
# + app restart; prod precompiles at image build.
pin "@rails/activestorage", to: "activestorage.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# D9 — QR decode for the in-app scanner (E2). Vendored ESM build of jsQR
# (vendor/javascript/jsqr.js); driven by controllers/qr_scanner_controller.js.
pin "jsqr", to: "jsqr.js"

# Gallery lightbox (#598) — vendored PhotoSwipe 5.4.4 ESM builds (MIT,
# dependency-free, self-contained). The lightbox shell is imported by
# controllers/lightbox_controller.js; the core loads on demand via the shell's
# `pswpModule` dynamic import, so its weight is only paid when a photo is
# actually opened. The stylesheet rides the Tailwind build
# (app/assets/tailwind/vendor/photoswipe.css).
pin "photoswipe", to: "photoswipe.esm.min.js"
pin "photoswipe/lightbox", to: "photoswipe-lightbox.esm.min.js"

# Mobile gallery viewer (#604) — vendored Swiper 11.2.10 as a self-contained
# ESM bundle (MIT). Built with esbuild from the npm package with only the modules
# the mobile "effect-cards" fullscreen viewer needs (EffectCards, Zoom, Keyboard,
# A11y) → default export Swiper + those named exports, ~91 KB. On touch/coarse
# pointers lightbox_controller.js dynamically imports this instead of PhotoSwipe;
# desktop keeps PhotoSwipe. Stylesheet rides the Tailwind build
# (app/assets/tailwind/vendor/swiper.css).
pin "swiper", to: "swiper.esm.min.js"

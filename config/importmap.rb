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

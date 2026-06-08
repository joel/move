# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"

# D9 — QR decode for the in-app scanner (E2). Vendored ESM build of jsQR
# (vendor/javascript/jsqr.js); driven by controllers/qr_scanner_controller.js.
pin "jsqr", to: "jsqr.js"

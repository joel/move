// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"

// Register the service worker (served at the root path → scope "/") so the
// browser treats the app as installable. Registration is idempotent.
if ("serviceWorker" in navigator) {
  navigator.serviceWorker.register("/service-worker.js")
}

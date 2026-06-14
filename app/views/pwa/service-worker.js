// Minimal service worker so the browser treats the app as installable. Chrome
// requires a registered service worker with a `fetch` handler before it offers
// the install affordance (omnibox icon on desktop, Add to Home screen on mobile).
//
// We intentionally do NOT cache anything yet: a no-op fetch handler lets every
// request pass through to the network so assets never go stale across deploys or
// tenants. Offline support / precaching is a deliberate follow-up.

self.addEventListener("install", () => self.skipWaiting())

self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()))

// Required for installability. Pass-through: do not call event.respondWith, so
// the browser handles each request normally.
self.addEventListener("fetch", () => {})

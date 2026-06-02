# PWA Verification

The app is a Progressive Web App. Buttons (`button_to` forms) behave differently than links (`link_to`) because they use POST/PATCH/DELETE requests. The service worker must not intercept these. Test buttons explicitly — do NOT assume a page that renders is also interactive.

## Button vs Link Distinction

- **Links** (`<a href>`) = GET requests = navigation. These are handled by Turbo Drive.
- **Buttons** (`<form method="post">`) = POST/PATCH/DELETE = mutations. These include toggles, deletes, sign out, form submits, and state transitions.

If links work but buttons don't, the likely cause is:
1. Service worker intercepting non-GET requests (check `if (request.method !== "GET") return` in `app/views/pwa/service-worker.js.erb`)
2. Stale cached JavaScript missing Turbo or Stimulus controllers
3. CSRF token mismatch from cached HTML

## PWA Button Tests

After logging in, test each button type the branch touches. Cover the full matrix of request methods, since each interacts with the service worker and Turbo differently:

```bash
# 1. POST toggle button (button_to, POST)
# A button that toggles a piece of state (e.g. a like/flag/favourite)
# Verify: state flips, count/label updates, no error, no full-page redirect

# 2. Form-submit button (form_with, POST)
# Fill the form fields, click the submit button
# Verify: record is created/updated, response renders (Turbo Stream or redirect), form resets

# 3. DELETE button (button_to, DELETE)
# Click Delete on an existing record
# Verify: record removed (via Turbo Stream or redirect), no error

# 4. PATCH in-place toggle (button_to, PATCH)
# Click a control that updates a record in place without a full reload
# Verify: the element updates without a page reload

# 5. State-transition button (button_to, POST/PATCH)
# Click a button that advances a record's lifecycle state
# Verify: the record transitions to the new state and the UI reflects it

# 6. Sign out button (POST/DELETE)
# Click Sign out in the sidebar
# Verify: session ends, redirects to home
```

## Service Worker Health Check

```bash
# Check service worker is registered and active
agent-browser eval "navigator.serviceWorker.ready.then(r => r.active?.state || 'no-sw')"

# Check service worker skips non-GET
agent-browser eval "fetch('/service-worker').then(r => r.text()).then(t => t.includes('request.method !== \"GET\"') ? 'GOOD: skips non-GET' : 'BAD: may intercept POSTs')"

# Check no stale caches
agent-browser eval "caches.keys().then(k => k.join(', '))"
```

The service worker source lives at `app/views/pwa/service-worker.js.erb` (the standard Rails PWA path).

## PWA Manifest Check

```bash
agent-browser eval "fetch('/manifest.json').then(r => r.json()).then(m => JSON.stringify({name: m.name, display: m.display, start_url: m.start_url}))"
```

Verify: `display` is `standalone`, `start_url` is `/`, `name` is set.

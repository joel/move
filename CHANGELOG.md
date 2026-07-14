# Changelog

All notable, user-facing changes are summarised here. Per-release notes (every
merged PR) live on [GitHub Releases](https://github.com/joel/move/releases).
This project adheres to [Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

## [v0.91.0] — 2026-07-14

### Added
- **Groundwork: item families now stay current on their own.** The grouping
  engine from v0.90.0 is wired to everything that changes your inventory —
  adding, renaming, moving or removing items, unpacking or deleting a whole
  box — so the families quietly recompute moments after you stop making
  changes. Still not visible on any screen; the gallery "Groups" view that
  shows them ships next (#631, part of #625).

## [v0.90.0] — 2026-07-14

### Added
- **Groundwork: the app can now group related items into families.** The
  engine that powers the upcoming gallery "Groups" view landed: it clusters
  things that belong together — all the AA batteries, chargers and power
  banks scattered across different boxes — using the same quiet hints that
  power search, with nothing to configure. Not visible on any screen yet;
  the Groups view ships next (#629, part of #625).

## [v0.89.0] — 2026-07-14

### Added
- **Search now understands what things are, not just what they're called.**
  When recognition catalogues a photo, it also privately notes each item's
  family — "batteries & power", "kitchenware" — and search uses that hidden
  hint, so searching "kitchenware" can surface a coffee maker whose name
  never says so. Nothing changes on screen: items stay just a name, and
  renaming an item drops the old hint so it can't mislead search. This is
  the first piece of the upcoming gallery Groups view, which will cluster
  related items scattered across boxes (#626, part of #625).

## [v0.88.2] — 2026-07-13

### Fixed
- **The camera can no longer stay locked after a dead connection.** If an
  upload hung on a completely stalled connection (one that never reports an
  error), the shutter and photo picker stayed disabled until the page was
  reloaded. Capture now frees itself after two minutes in that state — long
  past the point where the upload could still succeed — while keeping the
  v0.88.1 guarantee that a merely slow upload never loses a photo (#622).

## [v0.88.1] — 2026-07-13

### Fixed
- **A slow connection can no longer lose a photo taken right after another.**
  The new in-app camera briefly re-enabled its shutter if an upload took
  longer than 30 seconds (possible on slow cellular), and a second shot in
  that window could cancel the first upload unnoticed. The shutter now stays
  locked until the upload genuinely finishes, however slow the network (#620).

## [v0.88.0] — 2026-07-13

### Changed
- **The Capture screen now shoots photos inside the app, in portrait.** It
  used to hand off to your phone's camera app, which rotates to landscape
  with the device and can't be locked. Capture now opens a live viewfinder
  right on the page with a proper shutter button — so on an installed app it
  stays fixed to portrait, what you frame is exactly what recognition sees,
  and each shot flows straight in without switching apps. If the camera is
  unavailable or you deny access, the familiar tap-to-capture tile still
  works (and can pick from your gallery); on a computer, a "Use camera" link
  turns the webcam on only when you ask (#616).

## [v0.87.1] — 2026-07-13

### Fixed
- **Member roles no longer overflow the card on a phone.** On the Members
  screen, each member's permission level (the Admin badge or the role
  dropdown) was pinned beside the name and got clipped on narrow screens. It
  now sits neatly below the name on a phone and stays alongside it on wider
  screens (#613).

## [v0.87.0] — 2026-07-13

### Changed
- **Marking a box fragile is now front and centre.** The "fragile" control used
  to be tucked inside the box's ⋮ menu, so it was easy to miss. It now sits
  right on the box page as a tap-to-toggle chip — "Mark as fragile", which fills
  in to a "Fragile" pill once set (and prints FRAGILE on the box label). People
  with view-only access still see the fragile marker but can't change it (#610).

## [v0.86.0] — 2026-07-12

### Added
- **Invite anyone to a move by email.** A move admin can now invite people
  who don't yet have an account — not just existing teammates. Enter an email
  and a role on the Members screen and they get a personal link; accepting it
  walks them through creating an account (or signing in), joins them to your
  organisation and the move, and drops them straight onto it. Pending
  invitations are listed with resend and revoke, expired ones can be revived,
  and the "Invite" button is always available (previously it disappeared when
  there was no one left to add). Links are single-use, expire in 7 days, and
  an invitation to an archived move is declined rather than sending a dead
  link (#602 follow-up, #608).

## [v0.85.0] — 2026-07-12

### Changed
- **A touch-friendly photo viewer on your phone.** On a phone or tablet, tapping
  a photo in the Move gallery now opens a fullscreen viewer with a big swipeable
  image and a thumbnail strip along the bottom, so you can jump straight to any
  photo instead of swiping through them one by one. Pinch and double-tap zoom in
  to inspect a photo, the box each photo belongs to stays one tap away, and the
  position ("2 of 14") is always shown. On a computer the existing lightbox is
  unchanged, and each device only downloads the viewer it uses (#604).

## [v0.84.0] — 2026-07-11

### Changed
- **Swipe to edit or remove detected items on phones.** On the photo review
  screen, each detected item row used to show permanent edit/remove buttons
  that crowded the row on small screens. On a phone you now swipe a row
  right to edit its name, or left to reveal Remove — desktop keeps the
  familiar inline buttons, and the on-screen instructions name the gesture.
  Rows still work with a keyboard (tabbing to a hidden action slides it into
  view). Built on a new reusable swipe-to-reveal component (#602, #603).

## [v0.83.0] — 2026-07-11

### Changed
- **Gallery lightbox navigation is instant.** Swiping or arrowing between
  photos flips immediately to the already-loaded thumbnail and sharpens in
  place, instead of waiting for the full-size image (#598, #599).

### Fixed
- **Photo uploads no longer hang on a flaky connection.** A capture upload
  that can't reach storage promptly now falls back to uploading through the
  server instead of stalling the capture flow (#596, #597).

## [v0.82.0] — 2026-07-07

### Changed
- **Photo sizes are now made on the CDN edge.** Thumbnails and gallery sizes
  are resized at request time by the CDN instead of being pre-generated and
  stored by the app, and photo uploads go from the browser straight to
  storage — fewer moving parts, faster photo-heavy pages, no variant backlog
  after big capture sessions (#572).

## [v0.81.0] — 2026-07-07

### Changed
- **Capturing boxes is much faster.** Photos are downscaled on your device
  before upload (including iPhone HEIC and rotated shots), uploads no longer
  block the shutter, and image processing runs on a dedicated queue — batch
  snapping keeps pace with you, and a downscale problem can never block a
  submission (#541, #545, #547, #549, #558).
- **Photos moved to Cloudflare R2.** Production photo storage was migrated
  off the old SeaweedFS cluster (decommissioned after a corruption
  postmortem); the rare photo lost to that corruption now shows a graceful
  "photo unavailable" placeholder instead of a broken image (#537, #563,
  #567).

### Added
- **Self-healing pipeline (internal — no user-facing change).** A
  Sentry-driven loop can open autofix issues and generate candidate fix PRs
  with confidence-gated autonomy, plus Sentry release tracking wired into the
  deploy (#561, #555).

## [v0.80.0] — 2026-07-04

### Added
- **Scheduled encrypted database backups (internal — no user-facing change,
  but your data is now recoverable).** Production data — every organisation's
  rooms, boxes, items and recognition results — is backed up daily to an
  encrypted, deduplicated offsite repository (restic on Cloudflare R2) via a
  dedicated [kamal-backup](https://kamal-backup.dev) accessory, with
  retention (7 daily / 4 weekly / 6 monthly), post-backup integrity checks,
  restore drills and audit evidence. Photos live in separate object storage
  and are tracked as a follow-up (#537). Runbooks in
  `doc/project/backups.md` (#536).

## [v0.79.0] — 2026-07-04

### Added
- **Sentry performance monitoring (internal — no user-facing change).** Every
  request is now traced (timings for the request, its database queries and
  renders) and profiled, building on the v0.77.0 error monitoring. Traced
  queries get the same secret-scrubbing treatment as error reports: SQL
  string literals are redacted before anything leaves the app (#531).

## [v0.78.0] — 2026-07-04

### Added
- **Lookbook component browser (internal — no user-facing change).** The Phlex
  `Ui::*` design-system kit is now browsable per-component and per-state in
  [Lookbook](https://lookbook.build/) at `/lookbook` (development only — the
  gem and mount don't exist in production): 18 components, 60 scenarios,
  dark/light toggle, live reload, and the component source alongside each
  preview. New or changed `Ui::*` components ship with a preview from now on
  (#530).

## [v0.77.0] — 2026-07-04

### Added
- **Sentry error monitoring (internal — no user-facing change).** Production
  exceptions across web requests and background jobs are now captured in
  Sentry instead of only living in container logs. The SDK is dormant without
  a DSN (dev/test send nothing), the DSN flows through Doppler like every
  other secret, and a scrubbing hook keeps auth material — magic-link keys,
  session cookies, API tokens — out of the reports (#528).

## [v0.76.0] — 2026-07-04

### Added
- **Whole-app type checking (internal — no user-facing change).** The Phlex
  view and component layer — the last uncovered code — now carries checked type
  annotations, completing the rollout begun in v0.72.0: every method in every
  layer of the codebase (business actions, models, controllers, views) is
  statically type-checked, with the HTML/SVG tag vocabulary generated directly
  from the view library so a typo'd tag or helper is a build error (#525).
  Follow-up tracked in #527: tightening domain parameters to real model types.

## [v0.75.0] — 2026-07-04

### Added
- **Type-checked controllers with typed route helpers (internal — no
  user-facing change).** Completing the layer-by-layer rollout (v0.72–v0.74),
  every controller now carries checked type annotations, and route helpers are
  statically typed — a renamed route becomes a build error at every stale call
  site instead of a runtime 500. Every non-view layer of the codebase (business
  actions, models, controllers) is now covered by the type checker (#523).

## [v0.74.0] — 2026-07-03

### Added
- **Real model types for the type checker (internal — no user-facing change).**
  The static type checking introduced in v0.72–v0.73 now extends to every model,
  with genuine type information: community signatures for the Rails framework,
  generated schema-derived signatures per model (kept fresh by CI the same way
  the database schema file is), and checked annotations on every hand-written
  model method (#521).

### Fixed
- **Three latent nil-handling edge cases** in box volume math, item
  image-generation status, and review confidence display — each guarded a
  possibly-empty database value in a way that couldn't be statically proven
  safe; all three now read the value once and guard it directly. No behavior
  change in practice; the code is now provably nil-safe (#521).

## [v0.73.0] — 2026-07-03

### Added
- **Static type checking now covers the whole actions layer (internal — no
  user-facing change).** Completing the rollout started in v0.72.0, every pack's
  business-logic actions (all 15 packs, 31 more files) now carry checked inline
  RBS type signatures, with architecture tests that fail both drift directions:
  a method without an annotation, and a pack whose actions aren't wired into the
  checker. Adopting the wider net surfaced and hardened one latent edge — an
  account-deletion helper whose best-effort rescue could return `nil` against
  its declared array contract (#519).

## [v0.72.0] — 2026-07-03

### Added
- **Static type checking (internal — no user-facing change).** The business-logic
  layer (`app/actions`) is now type-checked by Steep reading inline RBS
  annotations — every method carries its signature in the code, checked
  merge-blocking in CI and at commit time, with an architecture test that keeps
  coverage at 100% as new actions land. Adopting the checker also surfaced and
  fixed a latent mixed String/Symbol hash key in the recognition-provider
  settings action. Conventions and roadmap live in
  `doc/project/type-checking.md` (#515).

## [v0.71.5] — 2026-07-02

### Fixed
- **Move cards now show real progress.** The moves list claimed "0 of 0 boxes
  packed" with an empty progress bar for every move — leftover placeholder
  numbers from an early build. Each card now shows the move's actual packed
  count, a proportional progress bar, and its true pending-review count,
  matching the numbers on the move's boxes page (#513).

## [v0.71.4] — 2026-07-02

### Security
- **Content-Security-Policy is now enforced.** The strict CSP shipped earlier in
  report-only mode (nonce-based `script-src`, locked-down framing and object
  sources) is now enforcing, after production ran violation-free: browsers block
  any script or resource the policy doesn't allow, closing the loop on the
  defense-in-depth baseline for a public multi-tenant app. Violation reports keep
  flowing to the built-in collector as ongoing telemetry (#493).

## [v0.71.3] — 2026-07-02

### Changed
- **Slimmer, safer production image (internal — no user-facing change).** The
  production Docker image no longer installs the test and development gem groups
  (`BUNDLE_WITHOUT="development:test"`): test frameworks and dev tooling — and the
  combined dev/test gems the un-excluded test group had silently kept in — are gone
  from the deployed image, shrinking its size and audit surface. Nothing changes for
  people using the app (#509).

## [v0.71.2] — 2026-07-02

### Fixed
- **Fragile box labels print correctly again.** On a box marked fragile, the
  printed label showed an empty colored bar instead of the FRAGILE banner and the
  box number was missing entirely. The banner now shows white FRAGILE text and the
  box number always prints at a readable size. Labels printed earlier from a
  completed bulk run keep the old rendering — start a new print run to regenerate
  (#508).

## [v0.71.1] — 2026-07-02

### Fixed
- **Broken photo thumbnails in the gallery and box views now display.** After
  v0.71.0 a couple of photos showed a broken-image icon. Two causes were fixed:
  display-image variants whose file had gone missing from storage are now detected
  and rebuilt (a new `images:repair` maintenance task), and Active Storage error
  responses are no longer cached by the CDN/browser — so a transiently-missing image
  can never stay broken after the file is restored (#486, #490).

## [v0.71.0] — 2026-07-01

### Changed
- **Modular architecture with Packwerk (internal — no user-facing change).** The
  codebase now enforces horizontal domain boundaries via Packwerk: **18 packages**
  (a shared `utility` kernel plus 17 domain packs) with strict dependency, privacy,
  visibility, and layered-architecture rules, merge-blocked in CI and checked at
  commit time. The core Move aggregate, identity, and application layer stay in the
  root; the periphery depends inward. Nothing changes for people using the app —
  this hardens the codebase against architectural drift (#437).

## [v0.70.0] — 2026-06-30

### Added
- **Start with a sample move to explore.** A brand-new account no longer lands on
  an empty app — it arrives with a ready-made **sample move** already filled with
  boxes and photographed items across a few rooms and packing states, so you can
  try browsing, search, the gallery and labels straight away. It appears on your
  moves list on its own (no setup), is clearly marked **Sample**, and you can remove
  it in one tap once you've had a look (#432).

## [v0.68.0] — 2026-06-29

### Changed
- **Sharper photo recognition.** Recognition no longer lists the things that
  aren't your belongings — the **floor**, walls, and the **moving box** itself
  stop showing up as inventory items, while furniture, rugs, and product boxes
  (which you *are* moving) are still captured. The detection prompt was rewritten
  around what you're actually packing, and recognition now runs on newer AI
  models (OpenAI GPT‑5.5, Google Gemini 3.5 Flash) tuned for accurate, consistent
  results. Per‑Move model overrides keep working unchanged (#425).

## [v0.67.0] — 2026-06-29

### Added
- **Gallery — browse every photo in a Move.** A new **Gallery** page (reached
  from the Menu) shows every photo across the whole Move in one recent-first
  grid, with each tile labelled by its box and room. Filter by room or switch to
  oldest-first, and tap any photo to open a full-screen lightbox you can step
  through with arrow keys or the on-screen controls, with a link straight to the
  photo's box. AI-generated item images appear too, marked with a ✨ Generated
  badge (#422).

## [v0.66.0] — 2026-06-29

### Added
- **Generate an image for a hand-added item.** A manually added item with no
  photo now offers an opt-in **"✨ Generate image"** button that creates an
  illustrative image and fills its card in place — useful when you want a visual
  for something you didn't photograph. It runs in the background and the card
  updates live (no reload); a failure leaves a one-tap retry. Generation uses the
  Move's own AI provider key (bring-your-own-key, reusing the OpenAI key that
  already powers recognition/search), so the button only appears when a key is
  set, and it never enters the photo-review flow (#416).

## [v0.65.0] — 2026-06-28

### Changed
- **Items and photos are now one surface — a photo-card grid.** Box contents
  render as a single grid: each captured photo is a card showing the things
  recognised in it as name chips, plus a placeholder card for each item added
  by hand. The capture panel is photo-first too (one card per photo, names as
  chips), and a photo opens straight into its per-photo detail. The inventory is
  still fully searchable and prints on the manifest/labels — it's just no longer
  shown as a separate parallel list (#412, #413, #414).
- **An item is just a name.** Per-item **category**, **tags** and **quantity**
  carried little weight for a move and are gone; the managed vocabulary is now
  **rooms only** (the spatial grouping that matters on a box) (#408, #410).
- **Fragile moved from the item to the box** and now prints on the box label, so
  a mover actually sees it — toggle it from the box's Manage sheet (#406).

### Removed
- The separate per-item detail list, the category & tag vocabularies, and the
  quantity control — along with their database tables, columns and AI-recognition
  fields (recognition now returns just a label + confidence).

## [v0.64.1] — 2026-06-28

### Security
- Closed a bypass in the manual-add packing guard: it now gates on the
  **validated** source photo (a settled orphan), not the raw `source_media_id`
  param, so a forged/stale id can no longer add an item to a sealed box (#403).

### Fixed
- Bumped the transitive `crass` gem `1.0.6 → 1.0.7` to clear advisory
  `GHSA-6jxj-px6v-747w` (CSS-parsing DoS) that was failing `bundle-audit`.

## [v0.64.0] — 2026-06-28

### Changed
- **Box detail — Capture is now the page's focal action.** The box identity is a
  lightweight, card-less text header (room/status chips → number → contents
  subtitle); the contextual hero is the prominent full-width action, with a quiet
  "Add manually" link beneath while packing (#400).
- **Coherent per-state hero:** packing → Capture · sealed → Mark in transit ·
  in transit → Mark unpacking · unpacking → Open unpacking · **unpacked → Delete
  box** (a finished box's natural next step).
- Box dimensions / volume / weight moved into the ⋮ "Manage box" sheet.

### Security
- Manual item-add is enforced packing-only at the action layer (web + MCP), so the
  hidden affordance can't be bypassed by a stale form or direct call; the
  per-photo review and recovery flows remain phase-agnostic.

## [v0.63.0] — 2026-06-28

### Added
- **Box detail "Manage box" bottom sheet** (⋮): a single contextual hero plus a
  sheet holding the remaining lifecycle step(s), Print label/manifest, Edit, and a
  destructive **Delete box** — decluttering the previously flat stack of competing
  action buttons (#398).
- `DELETE /boxes/:id` — soft-delete a box (cascading its items), restorable from
  the activity feed.

# Changelog

All notable, user-facing changes are summarised here. Per-release notes (every
merged PR) live on [GitHub Releases](https://github.com/joel/move/releases).
This project adheres to [Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

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

# Changelog

All notable, user-facing changes are summarised here. Per-release notes (every
merged PR) live on [GitHub Releases](https://github.com/joel/move/releases).
This project adheres to [Semantic Versioning](https://semver.org) and the
[Keep a Changelog](https://keepachangelog.com) format.

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

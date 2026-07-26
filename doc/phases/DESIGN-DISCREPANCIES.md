# Move — Design ⇄ Spec Discrepancy Log

**Purpose:** Record every place where the **written specification** (`doc/ai/v0.2/docs/*`) and the **Stitch design** (`projects/13869765800416404511`) disagree, plus the remediation path. Per the project rule *"get the Design right before building a customer-facing feature"*, no 🚫-blocked item may be implemented until its remediation is closed.

**Legend:** 🚫 blocking (a customer-facing screen is missing or contradictory) · ⚠️ non-blocking (resolvable with a documented decision) · ✅ resolved.

---

## ✅ §C2-REVIEW — Review model: per-item Keep/Correct/Ignore → per-photo edit/remove/navigate — RESOLVED

- **Spec (original):** Design Spec §4 C1/C2 + Workflow §5 described a per-box review **queue** (C1) and a **one-suggestion-per-screen** item-by-item flow (C2) with **Keep / Correct / Ignore** actions and an explicit **"no bulk confirm"** rule. This made one photo with N detections appear as N separate full-photo screens — reading as "one photo = one item", slow for boxes with hundreds of items, and with no way to add a missed item.
- **Resolution (2026-06-12, #143):** Product owner generated two new Stitch screens establishing a **per-photo** review model:
  - `Review Item-by-Item (Dark) - Responsive` → `screens/c2c865975366419998a26905710a85f3`
  - `Review Item-by-Item (Light) - Mobile View` → `screens/c5718290b1404577ad4946933875ffd6`
- **Model change (intentional, supersedes the spec):**
  - One screen **per photo** lists **every** item detected in it (incl. auto-confirmed) as an **editable field**; each row has a pencil (focus + select-all) and × (remove). Plus **"+ Add item"** and a single **"Next Photo"**.
  - **Keep / Correct / Ignore are removed.** Correction is inline (rename auto-saves on blur — `Items::Rename`); "Ignore" becomes × (`Items::MarkRemoved`); "Keep" is implicit.
  - **"Reviewed when shown":** opening a photo confirms its still-unreviewed items (`Reviews::MarkPhotoReviewed`) — this **replaces the "no bulk confirm" rule**, which no longer applies (there is no bulk-confirm *button*; advancing is navigation-only).
  - The **C1 queue is dropped**; the box's pending badge enters the photo walk directly.
- The recognition pipeline is unchanged — `RecognitionSuggestion`s are still produced as the audit trail; only their UI resolution path (the `RecognitionSuggestions::{Keep,Correct,MarkFalsePositive}` actions) was retired.
- Recorded in `README.md` §2 (C1 retired, C2 repointed).
- **Superseded in part (2026-07-17, #660 — user decision):** **"Reviewed when shown" is
  retired.** "Next Photo" read as pure navigation while the state change had already happened
  on open — misleading. Reviewing is now **explicit**: a **"Mark as Reviewed"** POST confirms
  the photo's unreviewed items and advances; **"Ignore"** advances without changing state; the
  pair renders at **both** the "Review Items" header and the footer (long item lists no longer
  bury the controls — the "single 'Next Photo'" wording above no longer holds). `GET
  reviews#photo` is side-effect-free (the `data-turbo-prefetch="false"` guards remain until
  #661). Read-only walks and already-reviewed box-walk photos keep the plain Next/Finish link.
  Composed from existing patterns (the advance-pill vocabulary); no Stitch screen shows the
  pair — backfill optional, same stance as §C1-MOVE-QUEUE.

---

## ⚠️ §C1-MOVE-QUEUE — Move-wide review queue has no Stitch screen — non-blocking, decided (#654)

- **Context:** the original per-box C1 "Review queue" was retired in #143 (the box badge enters
  the per-photo walk directly). #654 reintroduces the *concept* at **Move level**: with review
  otherwise reachable only box-by-box, there was no place to see — or clear — everything pending
  across a Move.
- **What shipped (product decision, user-confirmed):** a gallery-style **queue page**
  (`/moves/:id/review`, `ReviewQueuesController`) — a flat grid (**newest capture first** since
  #687; originally FIFO/oldest-first) of
  every photo still holding an unreviewed co-located item, each tile wearing a pending-item count
  badge and a "Box N · Room" caption — plus a **"Review all"** walk: the C2 photo screen in
  `?queue=move` mode, where Next crosses box boundaries and Finish returns to the queue. Entry
  points: a Menu-hub "Review" row (count-badged), the boxes-home pending-review stat (now a
  link), and a third "To review" pill on the Gallery's ViewToggle.
- **Design status:** no dedicated Stitch screen exists. The surface is **composed entirely from
  existing, designed patterns** — the Gallery grid tile (B1-derived), the Gallery ViewToggle, the
  C2 review screen, `Ui::SectionHeader`/`Ui::EmptyState`, and the `bg-tertiary/15 text-tertiary`
  pending tint from `BoxReviewBadge` — so no token or `Ui::*` addition and no DESIGN.md change.
- **Remediation:** optional — generate a Stitch screen for the queue page if/when the surface
  grows bespoke layout (filters, grouping). Not design-blocked; recorded in `README.md` §2 (C1′).
- **Update (2026-07-17, #660):** with reviewing now explicit (see §C2-REVIEW supersession), the
  queue walk advances **strictly forward** in queue order for everyone (previously
  editable Moves jumped to the head of the pending queue, which only worked because opening had
  already confirmed it). Ignored photos stay pending and resurface on the queue page at Finish;
  the "N more after this" count now counts only the forward remainder of the pass. Entering the
  walk from a **mid-queue grid tile** starts the pass there — photos before it in queue order
  are not revisited within that pass; they stay listed on the queue page, which Finish lands on.
- **Update (2026-07-18, #687):** the queue order flipped to **newest capture first**
  (`(captured_at, id)` DESC) — you review what you just shot while context is fresh; the gallery
  remains the recency-browsing surface and the queue drains toward older strays. "Strictly
  forward" in the walk now steps **next-oldest**, with the same no-ping-pong and termination
  guarantees; the 300-photo cap keeps the **newest** photos (the head of the queue is always the
  fresh work).
- **Update (2026-07-19, #699):** prev/next **navigation** arrows joined the walk's progress-bar
  row (the box-detail #694 nav recipe — no jump select, photos have no labels to jump by).
  Auto-advance and the "N more after this" count stay **strictly forward**, unchanged; the
  arrows are pure navigation — in queue mode prev steps to the nearest **newer still-pending**
  photo (a marked photo has left the set and stays done; ignored photos remain reachable; prev
  can pass above a mid-queue entry point), in box mode it walks the stable list (marked photos
  included). The pending-add controller (#690) now scopes the whole screen so the arrows guard
  in-progress edits too.

---

## ⚠️ §A2-DUPLICATE — Box-card duplicate control has no Stitch representation — non-blocking, decided (#658)

- **Context:** the §A2-REUSE-DIMS chips (below) solved size reuse on the *form*, but the
  "next box of the same size" case still costs a full form round-trip. #658 adds a one-tap
  **duplicate icon button** on each A2 box card that immediately creates a new box copying
  **only** the source's L/W/H (next free number, status `packing`, no room/description/
  weight/fragile/items — user-confirmed scope), then lands back on the index with the
  existing #336 highlight-ring + View-link toast.
- **Design status:** the canonical A2 Boxes-Home Stitch screens show no per-card action
  affordance. The control is **composed entirely from existing, designed patterns** — a
  small circular ghost icon button (surface-container-high hover tint, `text-muted`) overlaid
  on the card's top-right corner, a new `Icons::Duplicate` drawn to the existing icon
  conventions (24-viewBox, 1.6 stroke) — so no token or `Ui::*` addition and no DESIGN.md
  change. Rendered only when the Move is writable (same gate as the Add-box CTA).
- **Remediation:** optional — regenerate the A2 card in Stitch with the corner action if/when
  the card grows more per-card actions.

---

## ✅ §A2-REUSE-DIMS — "Add box" form had no way to reuse dimensions — RESOLVED

- **Need:** Packing a stack of identical cardboard boxes means re-typing the same
  Length / Width / Height on every Add Box (A2) form — tedious and a top cause of
  the "Add dimensions" warning badge. There was no Stitch design for reusing an
  already-used size.
- **Resolution (2026-06-13):** Generated a new mobile dark screen on the canonical
  design system (`assets/7d7093582cf24c509377983bb1b03565`):
  - `Add a Box - Reuse Dimensions` → `screens/e4c1538e273e4b3893c03449b32f99c5`
- **Model:** a **"Reuse dimensions"** label-caps heading + a horizontally
  scrollable row of pill **chips** sits directly above the L/W/H inputs. Each chip
  reads `40 × 30 × 25 cm`; the most-used size is the active (sage-filled) chip and
  shows a trailing count badge (`· 3`). Tapping a chip fills **Length / Width /
  Height only** — **weight stays blank** (contents differ per box). The chip row
  appears as soon as the Move has **any** box with complete dimensions (so reuse
  helps from box #2 of a stack onward); when none do, the form is unchanged (empty
  state). Most-used size first, with a `· N` badge once a size repeats, capped at
  6. No new table — presets are the distinct existing dimensions queried per Move
  (`Box.dimension_presets`).
- Recorded in `README.md` §2 (new A2 "Add box (form)" row).

---

## ✅ §A1 — "Create / select Move" screen — RESOLVED

- **Spec:** Design Spec §4 A1 requires a screen to list Moves (name, status, progress hint, box count, pending-review count), an empty state, archived read-only treatment, and a "Create Move" form (name, planned date, origin/destination address, unit system).
- **Resolution (2026-06-04):** Product owner created three mobile screens in Stitch covering A1, on the canonical dark design system:
  - `Select Move - List View` → `screens/36ff167acabc4cdea672180472c59fef`
  - `Select Move - Empty State` → `screens/fc59e54dc0924d32a7182ebf77361a0b`
  - `Create New Move - Form View` → `screens/aef244f9c1534e03a77a3f79a345df7d`
- Recorded in `README.md` §2; Phase **D1** design status flipped 🚫 → ✅.
- **Follow-up (non-blocking):** during D1 implementation, confirm the List View card shows all five data points (name, status, progress hint, box count, pending-review count) and that archived Moves render read-only; if any are absent from the design, refine the screen in Stitch. A desktop/responsive variant can be added later (see §VARIANTS).

---

## ✅ §E2 — "Scan QR" screen — RESOLVED

- **Spec:** Design Spec §4 E2 requires a scanner view with: authenticated-resolution state, unrecognized/foreign-QR state, read-only archived state, and role-aware actions on resolve. Domain Spec §12.1 + §8 `resolve_qr` require auth-gated resolution that does **not** change box status.
- **Resolution (2026-06-04):** Product owner created four mobile state screens in Stitch covering all required E2 states, on the canonical dark design system:
  - `Scan QR - Scanning State` → `screens/09263080e5d549b2b7f4450afc0a4daf`
  - `Scan QR - Resolved State` → `screens/8086fa259d204e2eb6bb56b9ff5e9fe2`
  - `Scan QR - Unrecognized State` → `screens/de9f2c2af36242fea3336c33dca99b5e`
  - `Scan QR - Archived State` → `screens/47000d2e4b61472b9f954dc4c73ca89d`
- Recorded in `README.md` §2; Phase **D9** is now fully ✅ (E1 + E2).
- **Follow-up (non-blocking):** during D9 build, confirm the Resolved State reveals only box identity (number + room), not contents, and exposes edit/unpack actions only for admin/contributor (viewer read-only) — refine in Stitch if needed.

---

## ✅ §E3 — "Unpacking mode" screen — RESOLVED

- **Spec:** Design Spec §4 E3 requires a box-items checklist, quick "mark removed", remaining count, "mark box unpacked", removed-items settling out, and archived read-only. Domain Spec §5.2 ties "mark unpacked" to marking all in-box items removed.
- **Resolution (2026-06-04):** Product owner created two mobile screens in Stitch on the canonical dark design system:
  - `Unpacking Mode - Active Checklist` → `screens/8e990c6d258d473cad16101819689246`
  - `Unpacking Mode - Box Unpacked Celebration` → `screens/2cb7c29c027247f8955004bda7b8740b`
- Recorded in `README.md` §2; Phase **D10** design status flipped 🚫 → ✅.
- **Follow-up (non-blocking):** during D10 build, confirm the Active Checklist surfaces the sticky remaining-count, a large per-item remove tap-target, removed items settling out, and a restore/undo affordance; refine in Stitch if any are absent.

---

## ✅ §F3 — "Settings / menu" screen (incl. MCP-token UI) — RESOLVED

- **Spec:** Design Spec §4 F3 requires: theme/dark-mode default, Move unit system, the static auto-confirm threshold (default 0.8) with a plain-language preview of its effect, an **Assistant / integrations** area to **create and revoke per-Move MCP integration tokens** (raw token shown once — Domain §4.13/§14), and account settings.
- **Resolution (2026-06-04):** Product owner created the Menu hub + Settings/Assistant screens in Stitch on the canonical dark design system:
  - `Menu Hub - Mobile View` → `screens/6f780b58de254181b2fc400cbdc65a2c`
  - `Settings & Assistant - Mobile View` → `screens/11d53a1166d9495db360705b06bb780c`
  - `Settings & Assistant - Responsive View` → `screens/02012642fd9444788cb7a8090d007884`
- Recorded in `README.md` §2; Phase **D13** design status flipped 🚫 → ✅. The D0/D1 "Menu" nav slot now has a real target.
- **Follow-up (non-blocking):** during D13 build, confirm the Settings screen includes the dark-mode-default toggle, metric/imperial unit toggle, the auto-confirm slider (0.8) with the "more review ↔ more hands-free" caption, and the Assistant panel's **shown-once raw-token reveal + active-token list with revoke**; refine in Stitch if any are absent.
- **Extension (2026-06-15, #185):** added a **"Recognition & AI"** card to the Settings screen for per-Move recognition provider selection + bring-your-own API keys (admin-only, write-only masked keys, strict-BYO "Key required" state). Product owner created two screens on the canonical dark design system:
  - `Settings & Assistant - AI Configuration (Mobile)` → `screens/f5d276c670364d758a0d5da723ed4f7b`
  - `Settings & Assistant - AI Configuration (Desktop)` → `screens/4587e39878b248b1a8370254a12af767`
  - Recorded in `README.md` §2. Built with `Views::Settings::RecognitionProviderPanel` + the `recognition-provider` Stimulus controller, against Phase D0 tokens.

---

## ⚠️ §DESIGN-SYSTEMS — Two "Move" design-system assets exist

- **Observation:** `list_design_systems` returns **two** assets, both named "Move":
  - `assets/7d7093582cf24c509377983bb1b03565` — **DARK, "Mindful Moving" Organic Minimalism**, pill buttons, Refined Palette, `page #2A2822` / `card #34312A`. **This is canonical** — it matches the project `designTheme` and the Refined-Palette decision.
  - `assets/29796e57b24c4993b2ace573bac8460b` — LIGHT, "Modern Corporate", 12px button radius, fixed 1280px grid. Older/alternate; do **not** use.
- **Remediation (adopted):** All screen generation and Phase D0 token work uses `assets/7d7093582cf24c509377983bb1b03565`. **Status: ✅ decided.**

---

## ✅ §GENERATION-ATTEMPT — All missing screens now created — RESOLVED

- **What happened:** A1, E2, E3, F3-Menu, F3-Settings were first dispatched via `mcp__stitch__generate_screen_from_text` (canonical dark design system, `deviceType=MOBILE`, brand prompts from each phase file). Every MCP call returned a client-side **timeout** and the render jobs did not register, so the path was abandoned.
- **Resolution (2026-06-04):** Product owner created all the screens **in the Stitch web UI** on design system **"Move" (dark, Mindful Moving)** = `assets/7d7093582cf24c509377983bb1b03565`. All recorded in `README.md` §2; all four blocked phases (D1, D9-E2, D10, D13) flipped 🚫 → ✅.
- **Five screens to create — progress:** ✅ (1) Create/Select Move *(3 screens, §A1)* · ✅ (2) Scan QR *(4 state screens, §E2)* · ✅ (3) Unpacking mode *(2 screens, §E3)* · ✅ (4) Menu hub *(§F3)* · ✅ (5) Settings + Assistant *(§F3)*. **All complete — no blocking discrepancies remain.**

---

## ✅ §RELEASE-TAGS — Phase release tags must be domain-named SemVer (PR #20 review)

- **Raised by:** Codex review on PR #20 (P2). The original plan tagged phase releases `ui-00`…`ui-13`, which conflicts with `AGENTS.md` Release Rules (SemVer `vMAJOR.MINOR.PATCH`) and with `release-bug-scan.yml` (triggers only on `v*` tags) — so a `ui-NN` release would silently skip the release bug scan and diverge from the `gh release create vX.Y.Z --generate-notes` flow.
- **Resolution (2026-06-04):** Replace `ui-NN` with **domain-named SemVer** tags `vMAJOR.MINOR.PATCH-<domain-slug>`, one minor bump per phase starting after the current latest tag (`v0.4.1`):
  `v0.5.0-design-foundation`, `v0.6.0-tenancy-and-moves`, `v0.7.0-boxes-home`, `v0.8.0-box-lifecycle`, `v0.9.0-capture-recognition`, `v0.10.0-items`, `v0.11.0-review`, `v0.12.0-vocabularies`, `v0.13.0-search`, `v0.14.0-qr-labels-scan`, `v0.15.0-unpacking`, `v0.16.0-members`, `v0.17.0-summary`, `v0.18.0-assistant-mcp`.
  The `v*` prefix keeps the Release Bug Scan + SemVer flow intact; the `-<slug>` makes the tag list self-describing (navigable by domain). Phase branches renamed to `feature/<slug>` to match. The old `ui-NN`/`phase-NN` tags were placeholders from before any domain existed.
- **Sibling plan aligned (same PR):** the domain-led plan also recommended `phase-00…phase-11` release tags with the *same* conflict. Updated to the SemVer/`v*` convention: `doc/ai/v0.2/prompts/Phase Index.md` ("Recommended release tags") and `doc/ai/v0.2/docs/Move - Workflow Specification v0.2.md` §4 step 16 + §12 (`gh release create vX.Y.Z`). Their `feature/phase-NN-…` *branch* names are left as-is — branch names don't hit the `v*`/SemVer rules, so they're not part of this discrepancy.

---

## ⚠️ §A2 — "Boxes Home" screen — non-blocking decisions (D2)

The canonical screen `Boxes Home (Dark) - Refined Palette`
(`screens/bda13a39e9cb48b99d72ea5af19041d7`) was implemented in Phase D2. Three
design ⇄ domain gaps were resolved with documented decisions rather than redesign:

- **Box has no name.** The Stitch cards show descriptive titles ("Everyday
  Dishes", "Library Heavy"), but Domain Spec §4.8 gives a Box only a number, room,
  dimensions, status and QR token — no name. **Decision:** cards title by **room**
  (the box number sits on the badge); "No room yet" when unassigned. Named boxes
  would be a domain change, not a D2 fix.
- **Item counts on cards.** The design shows real item ratios ("12/12 Items").
  Items land in **D5**, so D2 renders "No items yet" and a status-driven packed
  bar (sealed → full, packing → empty). The controller already computes the
  aggregate shape for D5 to populate.
- **Compact progress indicator.** Spec §4 requires a packed / pending-review /
  missing-dimensions indicator that is **not drawn on the canonical screen**.
  **Decision:** added subtly with design tokens (a summary card above the grid);
  no Stitch change needed.

Recognition processing/failed states (Design Spec §4 A2) use the existing
`Ui::RecognitionState` component; `BoxCard` exposes a `recognition_state` slot
wired to it, inert until RecognitionRun lands in **D4**. **Status: ⚠️ decided.**

---

## ⚠️ §B1 — "Box Detail" screen — non-blocking decisions (D3)

The canonical screen `Box Detail (Dark) - Refined Palette`
(`screens/bf7c4f4817464dd09f2b6d0b859cdf1d`) was implemented in Phase D3.

- **Lifecycle action buttons aren't drawn.** The screen shows the status chip and
  Capture/Add-item buttons, but Spec §4 also requires seal/unseal/in-transit/
  unpacking/unpacked actions. **Decision:** rendered with design tokens in the
  actions card (the valid `Box::TRANSITIONS` for the current status); no Stitch
  change needed.
- **Status copy.** The design chip reads "Open"; the app uses **"Packing"** for
  consistency with the A2 grid and the domain status name. Minor copy difference,
  not a redesign.
- **Items inventory + media gallery** are shown populated in the design, but Items
  land in **D5** and Media/capture in **D4**. D3 renders empty placeholders;
  capture/add-item entries are present but inert. The gallery will only ever show
  **full media, never crops** (Technical Foundation §13). **Status: ⚠️ decided.**

---

## ⚠️ §B2 — "Capture image" screen — non-blocking decisions (D4)

The canonical screen `Capture Image (Dark) - Responsive`
(`screens/99b7a1dce2924e21982207cc8812318f`) was implemented in Phase D4.

- **Upload, not a live camera.** The mockup shows a viewfinder with crosshairs/
  flip-camera. The app uses a **file upload** (`accept=image/*` + `capture=
  environment`, so mobile opens the native camera) → Active Storage, matching
  "online upload via Active Storage". A live getUserMedia stream was rejected as
  heavy/brittle for an upload pipeline. The viewfinder is rendered as the
  upload/preview area.
- **"Online & Syncing" pill is static.** Phase 1 is online-only with an honest
  failure on no-file/upload error (no offline queue). The pill shows "Online"; a
  live connectivity indicator is not built.
- **Session = recent box captures.** The right panel lists this box's recent
  media with live recognition state (polled), per the design.
- **Retry role-gating** is writable-Move-only until viewer/contributor roles land
  in D11 (the design/spec want admin/contributor). **Status: ⚠️ decided.**

(Light-desktop variant gap is tracked separately under §CAPTURE-LIGHT.)

---

## ⚠️ §D2 — "Manage categories / tags / rooms" screens — non-blocking decisions (D7)

The canonical screens `Manage Categories/Tags/Rooms (Dark) - Responsive`
(`screens/925ac259…`, `5ba9c352…`, `fab5b7b3…`) were implemented in Phase D7 as
three sibling surfaces from **one** controller + view (kind registry).

- **Dark-only in Stitch.** Rendered light from the Refined-Palette tokens, per
  §CAPTURE-LIGHT / §PALETTE.
- **Per-row Material Symbol icons → one medallion per kind.** The mockups give
  each value a bespoke glyph (kitchen/devices/bed…); our data model has no
  per-value icon, so each kind uses a single medallion (category grid / tag /
  boxes) tinted via `Ui::Chip` kinds (sage rooms · terracotta tags · neutral
  categories), satisfying "chips distinguish kinds".
- **Search / filter controls omitted.** The mockups show a search box and an
  applies-to filter tab row; search over vocab names is **D8** (phase §8 out of
  scope). The applies-to facet is still shown on each tag row. Sibling tabs
  (Categories | Tags | Rooms) replace the filter row for navigation.
- **No JS for add/rename.** Add is an always-visible form card; rename is an
  inline form via `?edit=<id>` (server-rendered, no Stimulus). Remove uses a
  Turbo `data-turbo-confirm` only when the value is in use.
- **Entry point deferred to D13.** The shared sidebar/bottom-nav "Settings/Menu"
  destination is still a stub (§NAV; routes land in D13). For D7 the surfaces are
  reached by URL and cross-link via the sibling tabs. **Status: ⚠️ decided.**

---

## ⚠️ §D1 — "Search" screen — non-blocking decisions (D8)

The canonical screen `Search (Dark) - Refined Palette`
(`screens/ca6172ef…`) was implemented in Phase D8.

- **Per-item images: ✅ resolved (#722).** D8 shipped text-first cards because
  the data model then had no per-item image. Since the items/photos
  simplification (#406) every item carries a representative photo via
  `Item#source_media`, and result cards now match the mockup: the photo fills a
  fixed-height area with the match badge overlaid, with a same-geometry
  placeholder tile for photo-less items. One residual gap stays open: the
  mockup's one-line description under the item name is omitted — items have no
  description field (only `name`), so there is no data to render there.
- **Match badges map to the hybrid signal.** "Exact Match" / "Related Item" in
  the design map to `Search::Items#matched_on` → exact / lexical / fuzzy /
  semantic, surfaced as a chip.
- **Voice/mic search omitted** (the mockup shows a mic button) — out of scope.
  The filter control is likewise deferred.
- **Nav entry point wired (not stubbed).** Unlike D7, Search is a primary
  destination, so it's linked from the shell via `Current.move` (Boxes + Search
  light up; Scan/Summary/Menu remain stubs until D9/D12/D13). **Status: ⚠️ decided.**

---

## ⚠️ §SIMILAR-SEARCH — "Find similar items" affordances (post-D8, #724)

Three entry points jump to the existing D1 search screen seeded with an item's
name (`/search?q=<name>`) — none has a Stitch representation (the C3 item-detail
screen was checked and carries no similar-items affordance):

- **C3 item detail**: a ghost "Search similar items" action under the form body —
  the looser companion to the precomputed same-group rail (#642), covering
  unclustered items and semantic cousins.
- **D1 result cards**: a "More like …" icon overlay (top-left; the match badge
  owns the top-right), sibling-anchor pattern per §A2-DUPLICATE.
- **Gallery lightbox**: per-photo item chips (bottom row, ≤6) in both viewers,
  tapping through to the seeded search. Chips render only when the photo sourced
  items.

Decision: build on the shipped D1 surface rather than a bespoke "similar items"
screen; the destination is designed, only the jump-off affordances are new.
**Status: ⚠️ decided.**

---

## ⚠️ §B1-UNPACK — In-place unpacking checklist on Box Detail (post-D10, #727)

While a box is `unpacking`, B1's contents grid becomes an in-place checklist:
photo-card name chips toggle remove/restore, photos with in-box items carry a
full-width "Unpack photo" row (the primary gesture — most photos hold one
item), standalone item cards gain Mark unpacked / Restore, and the header
ticks "N of M unpacked". No Stitch screen shows B1 in this state:

- **Treatment borrowed from E3** (`Unpacking Mode - Active Checklist`
  `screens/8e990c6d258d473cad16101819689246`, celebration `2cb7c29c…`): checked
  = accent-sage fill + check glyph, applied at chip/card scale on the existing
  D1 grid tokens. No new `Ui::*` component or token.
- **Sibling-anchor structure** per §A2-DUPLICATE: in unpacking mode only the
  photo tile is the review/recovery link; chips and the unpack row are
  siblings, never nested in the anchor.
- Controls render only for editable Moves while actively `unpacking` (matching
  the checklist's own gate); viewers/archived see checked truth read-only.
  **Status: ⚠️ decided.**

---

## ⚠️ §FIND-LIST — Personal find list (post-D10, #730)

A per-user picking list pinned from search results and rolled up by box
(`/find_list`, nav :search, menu-hub row). No Stitch screen exists for it:

- **Composed strictly from designed primitives**: SectionHeader, EmptyState,
  the gallery-group member-row treatment (thumb + name + locator), the
  Vocabularies list/stream mechanics, and the search card's §A2-DUPLICATE
  sibling-overlay pattern for the pin toggle (third overlay, bottom-right of
  the thumbnail — the two top corners stay owned by the match badge and the
  more-like-this control).
- **Struck ("Found") state borrows E3's checked treatment** (accent-sage fill +
  check glyph) at chip scale; box group headers reuse the "Box N · Room"
  locator vocabulary and link to the B1 in-place unpacking checklist
  (§B1-UNPACK).
- The #726 Stitch push-back scope now includes this screen. **Status: ⚠️ decided.**

---

## ⚠️ §E1/E2-IMPL — "Labels & Scan" build adaptations (D9)

E1 (`ea5a8a69…` + mobile) and the four E2 state screens were implemented in D9.

- **Label/manifest = Prawn PDFs from the box-detail Print buttons; no separate
  print-settings page.** The E1 Stitch screen shows a desktop "Print Label" page
  with a printer-destination dropdown and a copies stepper. Those are **browser-
  native** (the OS print dialog), and a live HTML preview of a PDF is redundant,
  so D9 ships the A7 label and A4 manifest as inline PDFs opened from "Print label
  (A7)" / "Print manifest (A4)" on the box detail. The A4 manifest itself carries
  the sensitive-content warning the design places on the print page.
- **Resolved state shows item count + status, not contents.** Matches the design
  (number, room chip, "N items inside", status, "Open box"); the contents live
  behind "Open box" (box detail), preserving "never leak contents on scan".
- **Archived state omits item thumbnails.** The Stitch archived sheet previews
  item thumbnails; D9 renders "ARCHIVED · READ ONLY" + identity + count + a
  read-only "View box" link. Thumbnails are a non-blocking enhancement.
- **Resolve is Move-scoped** (`/moves/:id/scan/:token`), not a bare `/scan/:token`
  — keeps the app-shell + nav context; still tenant-isolated by `qr_token`.
- **Status: ⚠️ decided** (user-approved plan).

---

## ⚠️ §PALETTE — Two colour systems coexist

- **Observation:** `designTheme` exposes a full Material-3 token set **and** a "Refined Palette" (`page-dark #2A2822`, `card-dark #34312A`, `page-light #F2ECE1`, `card-light #FAF6EF`, `accent-sage-dark #9FB089`). Many newer screens carry a `… - Refined Palette` variant; the design-system prose references the Refined Palette values directly.
- **Risk:** Implementers could pick the wrong surface colours and ship an inconsistent UI.
- **Remediation (adopted):** Treat the **Refined Palette as canonical** for surfaces/accent; import the Material-3 tokens as the semantic system for state colours (error/secondary/tertiary). Phase D0 encodes both and documents the mapping. Prefer `… - Refined Palette` screen variants as reference. **Status: ✅ decided** (recorded here + in `README.md` §3) — revisit only if product disagrees.

---

## ⚠️ §NAV — Mobile navigation pattern is under-determined

- **Spec:** Design Spec §3 deliberately leaves the mobile nav pattern open ("tab bar, drawer, floating action, or another suitable pattern"). The design-system prose specifies a **docked/floating bottom tab bar (4–5 icons)** on mobile and a **280px left sidebar** on desktop.
- **Risk:** "Open" spec vs. concrete design-system guidance.
- **Remediation (adopted):** Follow the design system — bottom tab bar (mobile) + left sidebar (desktop), active state = sage vertical pill. Built in Phase D0. The five destinations (Boxes, Search, Scan, Summary, Menu) come from §3. **Status: ✅ decided.** Note: the "Scan" (E2) and "Menu/Settings" (F3) destinations are now designed (§E2/§F3) but their *routes* aren't implemented until D9/D13 — at D0, wire the slots and point them at stub routes until those phases land.

---

## ⚠️ §AUTH — Logged-out / auth / welcome screens are not in the Design Spec

- **Observation:** The Design Spec enumerates in-app screens only. Sign-in / sign-up / magic-link / passkey / welcome are provided by the Rodauth shell and have **no** Stitch design.
- **Remediation (adopted):** Phase D0 applies the design tokens to the existing Rodauth + welcome views (re-skin, not redesign). No new Stitch screen required for Phase 1; revisit if product wants bespoke auth art. **Status: ✅ decided.**

---

## ⚠️ §CAPTURE-LIGHT / variant gaps — incomplete variant coverage

- **Observation:** A few screens lack a full light/dark × mobile/desktop matrix (e.g. Capture has no light-desktop variant; Manual Add has no dark-mobile variant). The Manage/Members/Summary screens are **dark-only**.
- **Risk:** Light-mode parity gaps could surface during implementation.
- **Remediation:** Non-blocking. Implement from the dark canonical screen + the Refined-Palette light tokens; if a light rendering is ambiguous, generate the missing variant in Stitch. Track per-phase under "Design references". **Status: ⚠️ watch.**

---

## ⚠️ §B1-CONTENTS — Box "Contents description" + AI suggest (#210) — non-blocking decisions

- **Observation:** Five new Stitch screens cover the contents-description surfaces (box detail panel, edit-form ✨ field with loading state, seal modal with generating/suggested/error states — desktop + mobile). The detail panel in the Stitch mock labels the description **"AI Suggested Contents"**.
- **Decision:** The shipped detail panel labels it **"Contents"** (sparkle icon retained), not "AI Suggested Contents" — the field is a plain, user-editable description that *may* have been AI-suggested or hand-typed or auto-generated deterministically, so a permanent "AI Suggested" label would misrepresent a hand-written value. The ✨ AI affordance lives on the **edit form and the seal modal** (where suggesting actually happens), per the agreed scope; the detail page shows a quiet "Add a description" link (→ edit) when empty rather than an inline suggest button.
- **Risk:** Cosmetic only.
- **Remediation:** None needed. **Status: ⚠️ decided.**

---

## ⚠️ §F1-INVITES — Member email invitations (D14, #608) — screens not in Stitch

- **Observation:** The Design Spec's F1 rule set anticipates invitations that create new users ("If an invite creates a new user, it must also add them to the Organization before adding the MoveMembership"), but the Stitch F1 screens (`b909f3a2…` responsive, `4ba298fa…` mobile) predate D14 and show no invite-by-email form, no pending-invitation rows, and no apex landing/unavailable pages.
- **Decision:** D14 shipped the surfaces from the Phase D0 tokens + existing F1 component idioms (SectionHeader CTA, Ui::Card forms, roster-row chrome for pending rows; apex pages mirror the session-handoff Expired card). The F1 header CTA is now unconditional (it anchors the always-rendered invite form — previously an org with no spare users showed no invite affordance at all).
- **Risk:** Cosmetic — the built surfaces extend an existing designed screen with its own idioms.
- **Remediation:** Generate the four missing Stitch screens (F1-with-pending, invite form states, apex landing, apex unavailable) on the canonical design system and record their `screens/<id>`s here + README §2. **Status: ⚠️ decided; Stitch backfill pending.**

---

## ⚠️ §B1-BOXNAV — Box detail prev/next + jump select (#694) — control not in Stitch

- **Observation:** The Stitch B1 box-detail screens predate the box-to-box navigation added by #694 (prev/next chevron arrows + a jump-to-box select in the back-link row, walking the Move's boxes in numeric label order).
- **Decision:** Composed entirely from existing shipped idioms — the header-bento icon-button recipe for the arrows and the members-row compact auto-submit select for the jump control — so the addition introduces no new visual vocabulary; hidden when the Move has fewer than two boxes.
- **Risk:** Cosmetic only.
- **Remediation:** Optional Stitch B1 backfill next time the screen is regenerated. **Status: ⚠️ decided.**

---

## Resolution tracker

| ID | Blocking? | Phase | Status | Action |
|----|-----------|-------|--------|--------|
| A1 | ✅ | D1 | resolved | 3 screens created (`36ff167a…`, `fc59e54d…`, `aef244f9…`) |
| A2 | ⚠️ | D2 | ✅ decided | box-name→room, item counts→D5, progress indicator added |
| B1 | ⚠️ | D3 | ✅ decided | lifecycle buttons added, items→D5 / gallery→D4 placeholders |
| B2 | ⚠️ | D4 | ✅ decided | file-upload (not live camera), static online pill, retry writable-only |
| C2 | ⚠️ | D6 | ✅ decided | quantity read-only on review (Keep = accept as-is); tweaks via Correct → C3 edit |
| D2 | ⚠️ | D7 | ✅ decided | one medallion/kind, search→D8, no-JS add/rename, entry point→D13 |
| D1 | ⚠️ | D8 | ✅ decided | text-first cards (no per-item images), mic/filter omitted, nav wired |
| E2 | ✅ | D9 | resolved | 4 state screens created (`09263080…`, `8086fa25…`, `de9f2c2a…`, `47000d2e…`) |
| E3 | ✅ | D10 | resolved | 2 screens created (`8e990c6d…`, `2cb7c29c…`) |
| F3 | ✅ | D13 | resolved | 3 screens created (`6f780b58…`, `11d53a11…`, `02012642…`) |
| PALETTE | ⚠️ | D0 | ✅ decided | Refined Palette canonical |
| F1-INVITES | ⚠️ | D14 | ✅ decided | built from tokens/F1 idioms; Stitch screen backfill pending |
| NAV | ⚠️ | D0 | ✅ decided | bottom tab + sidebar |
| AUTH | ⚠️ | D0 | ✅ decided | re-skin Rodauth/welcome |
| VARIANTS | ⚠️ | all | watch | fill light/missing variants on demand |
| RELEASE-TAGS | ⚠️ | all | ✅ resolved | domain-named SemVer `vX.Y.Z-<slug>` (PR #20 review) |
| RECOVERY | ⚠️ | post-D | ✅ decided | photo-recovery screen (orphaned/failed photo) ships as a state-variant of the designed C2 review/photo layout — same split (image left, action card right) + the shipped recognition-error caption; no new Stitch screen generated (#181) |
| B1-CONTENTS | ⚠️ | post-D | ✅ decided | 5 Stitch screens created (`c3adef35…`, `dce2995c…`, `78ec0a5f…`, `0b3ebf18…`, `e5dcff39…`); detail panel labelled "Contents" not "AI Suggested Contents"; ✨ on edit form + seal modal only (#210) |
| A2-DUPLICATE | ⚠️ | post-D | ✅ decided | box-card duplicate icon composed from existing patterns (ghost icon button + new `Icons::Duplicate`); Stitch A2 card backfill optional (#658) |
| B1-BOXNAV | ⚠️ | post-D | ✅ decided | detail prev/next arrows + jump select composed from existing idioms (icon-button arrows + compact auto-submit select); Stitch B1 backfill optional (#694) |
| INSURANCE | ⚠️ | post-D | ✅ decided | Insurance hub + dossier-run page composed from existing idioms (Menu row, SectionHeader + ha-cards, the label-print run/status chrome); the two PDFs are print artifacts (BoxManifestPdf language), not app screens; Stitch screen optional (#702) |

*Update this file whenever a discrepancy is found or closed. A 🚫 row must be ✅ before its phase leaves "Ready".*

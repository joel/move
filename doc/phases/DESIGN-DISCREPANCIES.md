# Move — Design ⇄ Spec Discrepancy Log

**Purpose:** Record every place where the **written specification** (`doc/ai/v0.2/docs/*`) and the **Stitch design** (`projects/13869765800416404511`) disagree, plus the remediation path. Per the project rule *"get the Design right before building a customer-facing feature"*, no 🚫-blocked item may be implemented until its remediation is closed.

**Legend:** 🚫 blocking (a customer-facing screen is missing or contradictory) · ⚠️ non-blocking (resolvable with a documented decision) · ✅ resolved.

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

## Resolution tracker

| ID | Blocking? | Phase | Status | Action |
|----|-----------|-------|--------|--------|
| A1 | ✅ | D1 | resolved | 3 screens created (`36ff167a…`, `fc59e54d…`, `aef244f9…`) |
| A2 | ⚠️ | D2 | ✅ decided | box-name→room, item counts→D5, progress indicator added |
| B1 | ⚠️ | D3 | ✅ decided | lifecycle buttons added, items→D5 / gallery→D4 placeholders |
| B2 | ⚠️ | D4 | ✅ decided | file-upload (not live camera), static online pill, retry writable-only |
| E2 | ✅ | D9 | resolved | 4 state screens created (`09263080…`, `8086fa25…`, `de9f2c2a…`, `47000d2e…`) |
| E3 | ✅ | D10 | resolved | 2 screens created (`8e990c6d…`, `2cb7c29c…`) |
| F3 | ✅ | D13 | resolved | 3 screens created (`6f780b58…`, `11d53a11…`, `02012642…`) |
| PALETTE | ⚠️ | D0 | ✅ decided | Refined Palette canonical |
| NAV | ⚠️ | D0 | ✅ decided | bottom tab + sidebar |
| AUTH | ⚠️ | D0 | ✅ decided | re-skin Rodauth/welcome |
| VARIANTS | ⚠️ | all | watch | fill light/missing variants on demand |
| RELEASE-TAGS | ⚠️ | all | ✅ resolved | domain-named SemVer `vX.Y.Z-<slug>` (PR #20 review) |

*Update this file whenever a discrepancy is found or closed. A 🚫 row must be ✅ before its phase leaves "Ready".*

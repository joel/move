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
- **Known related gap (not fixed here):** the sibling domain-led plan `doc/ai/v0.2/prompts/Phase Index.md` still recommends `phase-00…phase-11` tags, which have the *same* conflict with the SemVer/`v*` rules. Left unchanged — out of scope for this PR; worth a follow-up cleanup so both plans share the domain-named SemVer convention.

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
| E2 | ✅ | D9 | resolved | 4 state screens created (`09263080…`, `8086fa25…`, `de9f2c2a…`, `47000d2e…`) |
| E3 | ✅ | D10 | resolved | 2 screens created (`8e990c6d…`, `2cb7c29c…`) |
| F3 | ✅ | D13 | resolved | 3 screens created (`6f780b58…`, `11d53a11…`, `02012642…`) |
| PALETTE | ⚠️ | D0 | ✅ decided | Refined Palette canonical |
| NAV | ⚠️ | D0 | ✅ decided | bottom tab + sidebar |
| AUTH | ⚠️ | D0 | ✅ decided | re-skin Rodauth/welcome |
| VARIANTS | ⚠️ | all | watch | fill light/missing variants on demand |
| RELEASE-TAGS | ⚠️ | all | ✅ resolved | domain-named SemVer `vX.Y.Z-<slug>` (PR #20 review) |

*Update this file whenever a discrepancy is found or closed. A 🚫 row must be ✅ before its phase leaves "Ready".*

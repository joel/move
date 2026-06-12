# Move — Design-Led Implementation Phases

**Version:** 0.2 (design-anchored)
**Source of truth for visuals:** Google Stitch project **`Move Design`** (`projects/13869765800416404511`), accessed through the Stitch MCP server.
**Source of truth for behaviour:** `doc/ai/v0.2/docs/*` (Design, Domain, Technical Foundation, Workflow specs).
**Companion build plan:** `doc/ai/v0.2/prompts/*` (domain-led Phase 00–11). This plan does **not** replace it — it re-organises the same work around **screens** so that every customer-facing surface is delivered against a real design instead of a guess.

---

## 0. Why this plan exists

The instruction is explicit: **get the Design right before building a customer-facing feature, and never guess a screen.** Each phase below:

1. Is an **atomic chunk** — one branch, one PR, one release tag.
2. **Refers to the Stitch Design** by exact screen title + screen resource name, plus the matching Design-Spec section (`A1`, `B1`, …).
3. **Names the design tokens/components** it consumes from the Design Foundation (Phase D0).
4. **Flags any discrepancy** between the written spec and the Stitch design, with a remediation path (see `DESIGN-DISCREPANCIES.md`).

If a screen a phase needs does **not** exist in Stitch, the phase is marked **🚫 Blocked on design** and must not start until the screen is generated (via `mcp__stitch__generate_screen_from_text`) or supplied by product.

---

## 1. Phase list

| Phase | File | Release tag (SemVer) | Screens delivered | Design status |
|-------|------|----------------------|-------------------|---------------|
| D0 | `Phase D0 - Design Foundation.md` | `v0.5.0-design-foundation` | Design system, theming, nav chrome (stateless), style guide | ✅ Design complete |
| D1 | `Phase D1 - App Shell and Move Context.md` | `v0.6.0-tenancy-and-moves` | A1 Create/Select Move, global navigation | ✅ A1 designed (3 screens) |
| D2 | `Phase D2 - Boxes Home.md` | `v0.7.0-boxes-home` | A2 Boxes home | ✅ |
| D3 | `Phase D3 - Box Detail and Lifecycle.md` | `v0.8.0-box-lifecycle` | B1 Box detail | ✅ |
| D4 | `Phase D4 - Capture Image.md` | `v0.9.0-capture-recognition` | B2 Capture image | ✅ |
| D5 | `Phase D5 - Manual Add and Item Detail.md` | `v0.10.0-items` | B3 Manual add, C3 Item detail/edit | ✅ |
| D6 | `Phase D6 - Review Flow.md` | `v0.11.0-review` | C1 Review queue, C2 Review item-by-item | ✅ |
| D7 | `Phase D7 - Controlled Vocabularies.md` | `v0.12.0-vocabularies` | D2 Categories, Tags, Rooms | ✅ |
| D8 | `Phase D8 - Hybrid Search.md` | `v0.13.0-search` | D1 Search | ✅ |
| D9 | `Phase D9 - Labels QR and Scan.md` | `v0.14.0-qr-labels-scan` | E1 Box label & QR, E2 Scan QR | ✅ E2 designed (4 states) |
| D10 | `Phase D10 - Unpacking Mode.md` | `v0.15.0-unpacking` | E3 Unpacking mode | ✅ E3 designed (2 screens) |
| D11 | `Phase D11 - Members and Roles.md` | `v0.16.0-members` | F1 Members & roles | ✅ |
| D12 | `Phase D12 - Volume and Weight Summary.md` | `v0.17.0-summary` | F2 Summary & volume | ✅ |
| D13 | `Phase D13 - Settings Menu and Assistant.md` | `v0.18.0-assistant-mcp` | F3 Settings/menu + MCP token UI | ✅ F3 designed (3 screens) |

Each phase ships its own SemVer release per `AGENTS.md` Release Rules: a `vMAJOR.MINOR.PATCH-<domain-slug>` tag (e.g. `v0.7.0-boxes-home`) cut with `gh release create … --generate-notes`. The `-<domain-slug>` names the domain implemented so the tag list itself reads as a build history; the `v*` prefix keeps the Release Bug Scan (`release-bug-scan.yml`) and the SemVer release flow intact. (The earlier `ui-NN`/`phase-NN` tags were placeholders from before any domain was implemented — see `DESIGN-DISCREPANCIES.md` §RELEASE-TAGS.)

---

## 2. Screen coverage matrix

Every Design-Spec screen (`Move - Design Specification v0.2.md §4`) maps to exactly one phase. Canonical Stitch references are given as `<title>` → `screens/<id>`. Use `mcp__stitch__get_screen` with `projects/13869765800416404511/screens/<id>` to open the HTML/screenshot.

| Spec § | Screen | Phase | Canonical Stitch screen (desktop / mobile) |
|--------|--------|-------|--------------------------------------------|
| A1 | Create / select Move | D1 | `Select Move - List View` `screens/36ff167acabc4cdea672180472c59fef` · `Select Move - Empty State` `screens/fc59e54dc0924d32a7182ebf77361a0b` · `Create New Move - Form View` `screens/aef244f9c1534e03a77a3f79a345df7d` (all mobile) |
| A2 | Boxes home | D2 | `Boxes Home (Dark) - Refined Palette` `screens/bda13a39e9cb48b99d72ea5af19041d7` / `Boxes Home (Light) - Mobile` `screens/af60fe3e5f4148ea815de6780fb719f8` |
| B1 | Box detail | D3 | `Box Detail (Dark) - Refined Palette` `screens/bf7c4f4817464dd09f2b6d0b859cdf1d` / `Box Detail (Dark) - Mobile` `screens/29f0268b59e64a4d89e91f556b6cbfb5` |
| B2 | Capture image | D4 | `Capture Image (Dark) - Responsive` `screens/99b7a1dce2924e21982207cc8812318f` / `Capture Image (Dark) - Mobile` `screens/5aa6c04e3e624be8a72302ae97384a36` |
| B3 | Manual add item | D5 | `Manual Add Item (Dark) - Responsive` `screens/b37a2d0c54e246a8bfa0c031e6d705f6` / `Manual Add Item (Light) - Mobile` `screens/daf337c5f0af4e2c85f3bfba7047dbdf` |
| C1 | ~~Review queue~~ (retired, #143) | D6 | Per-box queue dropped — the box's pending badge now enters the per-photo walk directly. Old screens `688eefb9…` / `ee18e1c1…` superseded. |
| C2 | Review by photo | D6 (#143) | `Review Item-by-Item (Dark) - Responsive` `screens/c2c865975366419998a26905710a85f3` / `Review Item-by-Item (Light) - Mobile View` `screens/c5718290b1404577ad4946933875ffd6` — *edit / remove / navigate* model (supersedes `ad0e4e2b…` / `aa4b6520…`). |
| C3 | Item detail / edit | D5 | `Item Detail / Edit (Dark) - Responsive` `screens/7a371b5d5d44495d9766f8f08473e7d6` / `Item Detail / Edit (Dark) - Mobile` `screens/9fc6d2e9b40842fa8007bd4fac8b1c67` |
| D1 | Search | D8 | `Search (Dark) - Refined Palette` `screens/ca6172efa9fb4528b7dd0afa1fce9db2` / `Search (Dark) - Mobile` `screens/0d86caadc1c14327994fb51dcb3b90d5` |
| D2 | Categories / Tags / Rooms | D7 | `Manage Categories (Dark) - Responsive` `screens/925ac259021f4759af1a3ca3bf451464`, `Manage Tags (Dark) - Responsive` `screens/5ba9c352307f4ea28ff391d913c2f84a`, `Manage Rooms (Dark) - Responsive` `screens/fab5b7b3a84a41fda22d5e9e24849303` (+ mobile `a5776cdd…`, `7d22364c…`, `b2a8cebc…`) |
| E1 | Box label & QR | D9 | `Box Label & QR Print Preview (Dark)` `screens/ea5a8a69d7494226a3c93d7ad8f30635` / `… - Mobile` `screens/65a64f8df02b49488130244f0f60cc94` |
| E2 | Scan QR | D9 | `Scan QR - Scanning State` `screens/09263080e5d549b2b7f4450afc0a4daf` · `… Resolved State` `screens/8086fa259d204e2eb6bb56b9ff5e9fe2` · `… Unrecognized State` `screens/de9f2c2af36242fea3336c33dca99b5e` · `… Archived State` `screens/47000d2e4b61472b9f954dc4c73ca89d` (all mobile) |
| E3 | Unpacking mode | D10 | `Unpacking Mode - Active Checklist` `screens/8e990c6d258d473cad16101819689246` · `Unpacking Mode - Box Unpacked Celebration` `screens/2cb7c29c027247f8955004bda7b8740b` (all mobile) |
| F1 | Members & roles | D11 | `Members & Roles (Dark) - Responsive` `screens/b909f3a2e65c4ae09dbf77f615e81c86` / `… - Mobile` `screens/4ba298fa96a143279cad534328165807` |
| F2 | Volume & weight summary | D12 | `Summary & Volume (Dark) - Responsive` `screens/9c53bc10b02f4dd7864af8f3248abb02` / `… - Mobile` `screens/1bab812966eb41ca80cc7c2cbc7535b4` |
| F3 | Settings / menu (+ Assistant/MCP token) | D13 | `Menu Hub - Mobile View` `screens/6f780b58de254181b2fc400cbdc65a2c` · `Settings & Assistant - Mobile View` `screens/11d53a1166d9495db360705b06bb780c` · `Settings & Assistant - Responsive View` `screens/02012642fd9444788cb7a8090d007884` |

**Design references (not screens):**
- Design system token sheet — embedded in `projects/13869765800416404511` `designTheme.designMd` (mirrored in Phase D0).
- `direction_a_light_and_dark_mobile.html` — `screens/7062889364062299479` (original art direction).
- `Move - Design Specification v0.2.md` — `screens/11437822688574356621` (Stitch copy of the spec).

---

## 3. Palette decision (read before Phase D0)

Stitch carries **two** colour systems (see `DESIGN-DISCREPANCIES.md` §PALETTE):

- A full **Material-3 token set** (`surface`, `primary`, `on-primary`, …) — the systematic underlayer.
- A later **"Refined Palette"** (`page-dark #2A2822`, `card-dark #34312A`, `page-light #F2ECE1`, `card-light #FAF6EF`, `accent-sage-dark #9FB089`) used by the newest screens and referenced directly in the design-system prose ("`#34312A` over `#2A2822`").

**Decision adopted by this plan:** the **Refined Palette** is the canonical visual target; the Material-3 tokens are imported as the semantic foundation so component states (error, secondary, tertiary) remain systematic. Phase D0 wires both. The `… - Refined Palette` Stitch screens are therefore the preferred reference where a screen has multiple variants.

---

## 4. How every phase uses Stitch (mandatory)

For each phase, before writing any markup:

1. Open the canonical screen(s) with `mcp__stitch__get_screen` and read the HTML + screenshot.
2. Build with **Phlex components + the Phase D0 design tokens** — never invent spacing, colour, radius, or type values; pull them from the token sheet.
3. Reproduce **every state** the Design Spec lists for that screen (empty, loading, processing, failed, error, dark) — render-only is not "done".
4. If the screen and the written spec disagree, **stop and log it** in `DESIGN-DISCREPANCIES.md`, then follow the remediation path before coding.
5. Live-verify with `/product-review` against the seeded Docker app and compare side-by-side with the Stitch screenshot.

See `CLAUDE.md` / `AGENTS.md` → "Design source of truth (Google Stitch)" for the standing protocol.

---

## 5. Cross-phase rules (inherited from the Workflow spec)

- Issue first; one branch + PR per phase; the agent never merges and never releases before a human merge.
- Every phase preserves prior-phase behaviour and keeps `main` releasable.
- All customer/UI-facing strings live in `config/locales/*.yml` and render through Rails I18n — never hard-coded in Phlex.
- No offline mutation queue, no bounding-box/crop UI, no item value fields, no bulk confirm.
- Dark mode is the default theme; every list needs empty/loading/error states.

*End of index.*

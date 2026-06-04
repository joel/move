# Phase D13 — Settings, Menu & Assistant (MCP tokens)

**Release tag:** `ui-13`
**Branch:** `feature/ui-13-settings-assistant`
**Design status:** ✅ Design complete — F3 delivered as Menu hub + Settings/Assistant Stitch screens (`DESIGN-DISCREPANCIES.md` §F3)
**Depends on:** D0, D1
**Domain backing:** `prompts/Phase 10` (MCP tokens + tools). Domain Spec §4.13, §14; Technical Foundation §14; Design Spec §4 F3.

---

## 1. Goal
Deliver the app-/Move-level controls hub and the Assistant area where admins create and revoke per-Move MCP integration tokens. Close the nav-map "Menu/Settings" destination that D0/D1 stubbed.

## 2. Screens delivered
- **F3 — Settings / menu** incl. the **Assistant / integrations** panel (`Design Spec §4 F3`). ✅ Designed as a Menu hub + a Settings/Assistant screen.

## 3. Design references (open before coding)
- `Menu Hub - Mobile View` → `screens/6f780b58de254181b2fc400cbdc65a2c` (top-level nav hub)
- `Settings & Assistant - Mobile View` → `screens/11d53a1166d9495db360705b06bb780c`
- `Settings & Assistant - Responsive View` → `screens/02012642fd9444788cb7a8090d007884` (desktop)
- This closes the "Menu" nav slot stubbed in D0/D1.

## 4. Content & behaviour (from spec)
- Theme (dark-mode **default**); Move unit system; **static auto-confirm threshold** (default 0.8) with a plain-language preview of its effect ("more review vs more hands-free"); account settings.
- **Assistant / integrations:** create and **revoke per-Move MCP integration tokens**; **raw token shown once**; list active tokens with name, created-by, last-used, and revoke action (Domain §4.13).
- Threshold static in Phase 1 (no adaptive per-category). Messaging channels (Telegram/WhatsApp) out of scope.

## 5. Domain & actions required
- `App::MoveIntegrationTokens::Create` (admin-only; raw token shown once, `token_digest` stored) / `Revoke` (sets `revoked_at`; independent of MoveMembership).
- MCP auth resolves a bearer token → Move + Organization, sets `Current.source = :mcp`, enforces not-revoked (Technical Foundation §14.1). Initial tools wired to shared actions: `search_items`, `get_box_contents`, `list_boxes`, `add_item_to_box`, `add_media_to_box`, `move_item`, `mark_unpacked`, `get_volume_summary` (Domain §14).
- Settings writes: theme pref, Move `unit_system`, `auto_confirm_threshold`. Audit records source `mcp` for token use.

## 6. ✅ Design status (resolved)
F3 is designed as a Menu hub + a Settings/Assistant screen (mobile + desktop — see §3); recorded in `README.md` §2 and `DESIGN-DISCREPANCIES.md` §F3. During build, confirm the Settings screen includes the dark-mode-default toggle, metric/imperial unit toggle, the auto-confirm slider (0.8) with the "more review ↔ more hands-free" caption, and the Assistant panel's **shown-once raw-token reveal + active-token list with revoke**; refine in Stitch if any are absent.

## 7. Acceptance criteria
- [ ] Menu hub and Settings/Assistant layouts match the Stitch screens.
- [ ] Theme toggle (dark default), unit system, and threshold (with plain-language preview) all persist.
- [ ] Admin can create an MCP token (raw value shown once) and revoke it; revoke is independent of membership.
- [ ] A revoked token is rejected by MCP auth; active token can call the initial tools through shared actions; audit logs source `mcp`.
- [ ] Non-admins cannot manage tokens (UI + server).
- [ ] Dark default; strings I18n.

## 8. Runtime verification
`/product-review` as admin: change theme/unit/threshold (verify preview + persistence) → create an MCP token (verify shown-once + copy) → exercise a tool with it (e.g. `list_boxes`) → revoke → confirm the tool now fails. Verify contributor/viewer have no token UI.

## 9. Out of scope
Adaptive thresholds, messaging channels, org-wide tokens (explicitly forbidden — Workflow §14).

## 10. Phase audit trail
_Fill on execution:_ Issue: · PR: · Menu/Settings Stitch screen ids: · Verification: · Release `ui-13`:

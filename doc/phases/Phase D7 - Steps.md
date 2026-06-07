# Phase D7 — Controlled Vocabularies · Steps (flight recorder)

Append-only log of how the work unfolded. Companion to
`Phase D7 - Controlled Vocabularies.md`.

- **Issue:** #69 — Phase D7 — Controlled Vocabularies management.
- **Branch:** `feature/vocabularies` (model foundation already merged here in
  c8aa4bd: DB case-insensitive uniqueness #59, `tags.applies_to`, `Move#admin?`).

## Scope decisions

- **One controller, not three.** The three vocabularies are near-identical, so a
  single `VocabulariesController` with a `:kind` route segment serves all three.
  A non-persisted `Vocabulary` registry (`app/models/vocabulary.rb`) maps a kind
  to its model, Move association, chip tint, medallion icon, applies-to facet and
  bulk usage counts. One view (`Views::Vocabularies::Index`) and one form
  component render every surface. KISS over three duplicated stacks.
- **Generic actions.** `Vocabularies::Create | Update | Remove < BaseAction`
  driven by the registry. Rename propagates via FK (a single column update — no
  cascade). Remove detaches via model `dependent:` (categories/rooms nullify,
  tags drop their `item_tags`) inside a transaction and reports the detached
  count. Each emits a `vocabulary.*` `Rails.event`.
- **Authorization (record = Move).** `VocabularyPolicy`: `index?` open to any
  signed-in member (read-only view); `create?/update?/destroy?` admin-only **and**
  writable (non-archived) Move. Non-admins get no edit affordance and the API
  rejects their writes (403).
- **In-use confirmation.** Bulk usage counts drive a Turbo `data-turbo-confirm`
  on the remove button **only** when the value is in use; unused values delete
  straight away. Detachment is server-side regardless.
- **No-JS add/rename.** Add is an always-visible form card; rename is an inline
  form via `?edit=<id>`. Fully server-rendered and testable without a JS driver.
- **Design deltas** logged in `DESIGN-DISCREPANCIES.md` §D2: dark-only screens
  rendered light from Refined-Palette tokens; one medallion per kind (no
  per-value glyphs); search/filter deferred to D8; Settings entry point deferred
  to D13 (reach by URL + sibling tabs for now).

## Routing

`moves/:move_id/vocabularies/:kind` (index/create) and `…/:kind/:id`
(update/destroy), `:kind` constrained to `categories|tags|rooms` so an unknown
kind 404s at the routing layer. NOTE: a bare `scope "vocabularies/:kind"` inside
the `resources :moves` block produced a **broken** path order
(`/vocabularies/:kind/moves/:id`); declaring the four routes inline (like the
existing `capture` routes) nests correctly under `/moves/:move_id/`.

## Commits

| sha | what |
|-----|------|
| c8aa4bd | (pre-existing) model foundation: DB uniqueness #59, tag applies_to, Move#admin? |
| b35ed73 | Vocabulary kind registry + medallion icons (tag/category/trash) |
| fda6d4e | admin-only VocabularyPolicy |
| b009915 | create/update/remove vocabulary actions |
| c30ffab | management surfaces — controller, routes, views, form, I18n |
| 90e3567 | seed showcase vocabulary data (member account, applies-to variety, unused values) |
| fb24cb3 | system spec for the management flows |

## Verification

- Unit suite: `372 examples, 0 failures` (+ vocab model/policy/action/request specs).
- System suite (`rack_test`): `27 examples, 0 failures` (+ vocab management spec).
- Lint (RuboCop) + Brakeman (`0 warnings`) green.
- Seeds run twice — idempotent (5 rooms, 5 categories, 6 tags).
- Live `/product-review` (admin demo@example.com on `acme`): all three surfaces
  render to the Stitch design (sidebar, header, kind-tinted sibling tabs, add
  form, medallion rows with usage meta); tags show applies-to chips + select;
  add / inline-rename / remove all work with flashes; unused remove deletes with
  no confirm, in-use remove shows the pluralized Turbo confirm and detaches the
  boxes (Bedroom → 2 boxes nullified). Member (member@example.com) sees the list
  read-only — no add form, 0 edit/remove affordances. Mobile 393×852: no
  overflow, bottom tab bar. No Bullet N+1, no runtime errors.

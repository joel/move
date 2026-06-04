# Move - Implementation Phase Index

**Version:** 0.2
**Purpose:** Sequential implementation plan for the Move Rails application.
**Use:** Each phase has its own Markdown file and should become its own tracked issue/PR unless the human lead explicitly splits it further.

---

## Product Phase 1 target

The first releasable product must include the product-faithful loop:

1. Organization subdomain tenancy.
2. Move creation and MoveMembership roles.
3. Boxes, rooms, categories, tags, items, and media.
4. Image-only recognition through a provider-agnostic adapter.
5. Customer/UI-facing strings are stored in YAML I18n files even though Phase 1 is English-only.
5. Review flow with keep, correct, and false detection.
6. Hybrid PostgreSQL search using full-text, `pg_trgm`, and `pgvector`.
7. QR scan, opaque labels, authenticated manifest.
8. Unpacking flow and volume/weight summary.
9. Per-Move MCP integration tokens and initial tools.

No offline mutation queue, no video capture, no item value fields, no bounding boxes/crops, no bulk confirm.

---

## Global implementation guardrails

- Phase 1 is English-only, but every customer/UI-facing string must be defined in YAML locale files and rendered through Rails I18n. Do not hard-code UI copy in Phlex components, views, controllers, mailers, notifications, or validation-facing messages.
- Recognition providers normalize vision output into provider-independent objects with `label`, `confidence`, and `count`. OpenAI and Anthropic adapters may differ in granularity, but domain records must not leak vendor schema.

## Phase sequence

| Phase | File | Goal |
|-------|------|------|
| 00 | `Phase 00 - Base Shell Audit and Spec Alignment.md` | Audit the generated shell and align it with the required foundation without rebuilding working pieces. |
| 01 | `Phase 01 - Subdomain Tenancy and Organizations.md` | Add Organization, OrganizationMembership, subdomain resolution, and tenant scoping. |
| 02 | `Phase 02 - Moves and Move Memberships.md` | Add Move, MoveMembership, roles, move selector, and archived read-only behavior. |
| 03 | `Phase 03 - Controlled Vocabularies and Boxes.md` | Add rooms, categories, tags, boxes, QR token basics, box lifecycle, and measurements. |
| 04 | `Phase 04 - Items Media and Manual Inventory.md` | Add media upload, manual item creation, item lifecycle, item movement, and media gallery. |
| 05 | `Phase 05 - Recognition Pipeline.md` | Add provider-agnostic recognition, RecognitionRun, RecognitionSuggestion, jobs, failure/retry. |
| 06 | `Phase 06 - Review Flow Conflicts and Activity.md` | Add review UX/actions, conflict rules, no-overwrite safeguards, and audit feed coverage. |
| 07 | `Phase 07 - Hybrid Search.md` | Add full-text, trigram, pgvector, embedding jobs, hybrid ranking, and search UI/MCP support. |
| 08 | `Phase 08 - QR Labels Manifests and Scan Flow.md` | Add auth-gated QR resolution, A7 label, A4 manifest, and scan flow. |
| 09 | `Phase 09 - Unpacking Summary and Measurements.md` | Add unpacking checklist, mark unpacked, restored items, volume/weight summary. |
| 10 | `Phase 10 - MCP Integration Tokens and Tools.md` | Add per-Move MCP tokens and initial assistant tools. |
| 11 | `Phase 11 - Product Hardening and Release Readiness.md` | Tighten system tests, security, runtime journeys, performance, and release readiness. |

---

## Cross-phase rules

- Every phase starts with an issue.
- Every phase gets a branch and PR.
- The agent never merges.
- The agent never creates a phase release before human merge.
- Every phase must preserve previous phase behavior.
- Every phase must update factories and seed/test data where needed.
- Every phase must include runtime verification notes in its PR.
- No phase may reintroduce offline mutations, bounding boxes/crops, value fields, or bulk confirm without a new explicit spec change.

---

## Recommended release tags

Use two-digit tags for lexical order:

```text
phase-00
phase-01
phase-02
...
phase-11
```

---

*End of phase index.*

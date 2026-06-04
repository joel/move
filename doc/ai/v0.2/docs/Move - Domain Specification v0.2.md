# Move - Domain Specification

**Version:** 0.2.2
**Status:** Product/domain source of truth after clarification
**Scope:** Domain model, lifecycles, behavior, permissions, and product invariants. Technical implementation details live in `Move - Technical Foundation Specification v0.2.md`.

---

## 0. Version 0.2 decisions

This version replaces the original draft where it conflicts.

- Move belongs to Organization.
- Organization tenancy is for account separation and is resolved by subdomain.
- Move access is controlled by MoveMemberships.
- Move roles are exactly `admin`, `contributor`, and `viewer`.
- Rooms, tags, and categories are managed vocabularies scoped to a Move.
- Box references one room. There is no origin-room/destination-room split in Phase 1.
- Offline capture and offline edits are out of scope for Phase 1.
- Recognition is provider-agnostic, image-only in Phase 1, and uses `RecognitionRun` plus `RecognitionSuggestion`.
- No bounding boxes, source crops, crop coordinates, or crop-highlight behavior are part of the domain.
- Hybrid PostgreSQL search is the target: full-text + `pg_trgm` + `pgvector`.
- Auto-confirm threshold is static per Move in Phase 1, default 0.8.
- Adaptive confidence thresholds are deferred.
- Item value fields are out of scope for Phase 1.
- Bulk confirm / mark-all-reviewed is out of scope.
- Media is retained indefinitely unless a later explicit deletion policy is introduced.
- MCP uses revocable per-Move integration tokens that may mutate data.
- The product is English-only in Phase 1, but all customer/UI-facing strings must be loaded from YAML I18n files.

---

## 1. Purpose

Move helps a person catalogue the contents of moving boxes with very little effort and find any item later.

The Phase 1 core loop is:

> Capture an image into a box -> recognition proposes items -> high-confidence items are auto-confirmed -> uncertain items are reviewed -> confirmed items become searchable across the Move.

An MCP server exposes a safe subset of the same capabilities to an AI assistant through a per-Move integration token. Messaging channels such as Telegram or WhatsApp are outside the web app scope.

---

## 2. Design principles

These principles resolve ambiguous choices.

### Identify, do not merely classify

Recognition should name the thing as specifically as possible: title, brand, model, color, label, or other identifying detail. Two distinct books are two searchable items, not `books x2`.

### Optimize for the search-in-three-years moment

Packing is temporary; finding something later is the durable promise. When packing convenience and future findability conflict, findability wins.

### Be honest about processing

The app is online-first for Phase 1. It must clearly show uploaded, queued, processing, failed, retried, and recognized states. It must not pretend offline capture or offline edits are supported.

### Do not waste the user's attention

High-confidence suggestions can be auto-confirmed. Low-confidence or conflicting suggestions must be reviewed one by one. Bulk confirmation is intentionally not included in Phase 1.

### Secure by default

No box contents are readable without authentication and Move access. Exterior labels are opaque.

---

## 3. Ubiquitous language

| Term | Meaning |
|------|---------|
| Organization | The SaaS account/workspace resolved by subdomain. Owns Moves and OrganizationMemberships. |
| OrganizationMembership | A user's account-level membership in an Organization. This is not the same as a Move role. |
| Move | A single relocation under an Organization. Owns boxes, rooms, tags, categories, media, items, recognition runs, and MoveMemberships. |
| MoveMembership | A user's role on a Move: admin, contributor, or viewer. |
| Box | A physical container being packed. Has a unique number within the Move, one room, dimensions, status, and permanent QR token. |
| Media | A captured file attached to a box. Phase 1 accepts image media only. |
| RecognitionRun | One attempt to process a Media file through a recognition provider. |
| RecognitionSuggestion | A normalized provider-independent proposed item from a RecognitionRun. |
| Item | A single identifiable thing inside one box. |
| Category | A managed per-Move vocabulary for an item's primary type. Each item has at most one category. |
| Room | A managed per-Move vocabulary for where a box belongs. |
| Tag | A managed per-Move optional label applied to items or boxes. |
| Manifest | A detailed contents listing for a box. Authenticated and never public. |
| MCP integration token | A revocable per-Move token that lets an assistant access allowed MCP tools. |

There is no `Detection` domain entity in Phase 1. Recognition suggestions do not store bounding boxes.

---

## 4. Entity model

### 4.1 Organization

The SaaS account boundary.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| name | string | required |
| slug | string | unique; used as subdomain |
| settings | jsonb | optional account settings |
| created_by_user_id | uuid | creator; creator becomes account admin |

Relationships:

- Organization has many OrganizationMemberships.
- Organization has many Moves.
- Organization owns tenant data for scoping and authorization.

### 4.2 OrganizationMembership

Account-level access. This is deliberately not a product-facing Move role.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | required |
| user_id | uuid | required |
| account_admin | boolean | default false |

Rules:

- Unique `(organization_id, user_id)`.
- A user must have an OrganizationMembership before they can have a MoveMembership in that Organization.
- OrganizationMembership grants account presence. MoveMembership grants Move permissions.

### 4.3 Move

The main working unit.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | required |
| name | string | required |
| planned_date | date | optional |
| origin_address | string | optional |
| destination_address | string | optional |
| unit_system | enum(`metric`, `imperial`) | default `metric` |
| status | enum(`planned`, `started`, `finished`, `archived`) | default `planned` |
| auto_confirm_threshold | decimal | default 0.8; static in Phase 1 |

Rules:

- Move belongs to exactly one Organization.
- Move owns boxes, rooms, tags, categories, media, items, recognition runs, suggestions, memberships, and integration tokens.
- Archived Moves are read-only.

### 4.4 MoveMembership

Move-specific access.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| user_id | uuid | required |
| role | enum(`admin`, `contributor`, `viewer`) | required |

Rules:

- Unique `(move_id, user_id)`.
- User must belong to the same Organization.
- Move creator becomes admin by default.
- A Move cannot be shared with someone outside its Organization.

### 4.5 Room

A managed per-Move vocabulary.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| name | string | unique within Move |

Rules:

- Rename updates the displayed room name everywhere.
- Remove detaches the room from boxes after confirmation if in use.

### 4.6 Category

A managed per-Move vocabulary for item primary classification.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| name | string | unique within Move |

Rules:

- An item has at most one category.
- Recognition may suggest a category only from this controlled vocabulary or leave it blank.
- No free-text category values are created from item forms.
- Rename updates all associated items.
- Remove detaches category from items after confirmation if in use.

### 4.7 Tag

A managed per-Move optional label.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| name | string | unique within Move |
| applies_to | enum(`item`, `box`, `both`) | required |

Rules:

- No free-text tags.
- Rename updates all associated records.
- Remove detaches the tag from associated records after confirmation if in use.

### 4.8 Box

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| number | string | unique within Move; generated by default; user override allowed on create |
| qr_token | string | permanent opaque token scoped to the Box |
| room_id | uuid | optional, required before sealing |
| length | measurement | optional; canonical storage through measurement support |
| width | measurement | optional |
| height | measurement | optional |
| weight | measurement | optional |
| status | enum(`packing`, `sealed`, `in_transit`, `unpacking`, `unpacked`) | default `packing` |

Rules:

- Box belongs to exactly one Move.
- Box number uniqueness is `(move_id, number)`.
- QR token is permanent and not regenerated in Phase 1.
- Volume is derived from dimensions and never edited as source-of-truth.
- Dimensions and weight use canonical storage with display conversion from Move unit system.
- Box can have many items, media files, and tags.

### 4.9 Media

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| box_id | uuid | required |
| media_type | enum(`image`, `video`) | Phase 1 accepts only `image`; `video` reserved |
| captured_at | timestamp | required |
| captured_via | enum(`web`, `mcp`) | required |
| file_attachment | Active Storage | required |

Rules:

- Media belongs to one box.
- Media is retained indefinitely.
- Items and recognition suggestions may reference the source media.
- No crop, bounding-box, or frame coordinate fields are stored.

### 4.10 RecognitionRun

One provider execution attempt for one Media record.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| box_id | uuid | required |
| media_id | uuid | required |
| provider | string | provider adapter name, not vendor schema |
| provider_model | string | optional model label |
| status | enum(`queued`, `processing`, `succeeded`, `failed`, `partially_succeeded`) | required |
| error_code | string | nullable |
| error_message | string | nullable, sanitized |
| metadata | jsonb | provider-independent, redacted operational metadata only |
| started_at | timestamp | nullable |
| completed_at | timestamp | nullable |

Rules:

- RecognitionRun never exposes vendor-specific response structure to domain code.
- Do not store raw provider responses in domain tables.
- Failed runs can be retried by admin/contributor.
- Retry creates a new RecognitionRun.

### 4.11 RecognitionSuggestion

A normalized proposed item.

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| box_id | uuid | required |
| media_id | uuid | required |
| recognition_run_id | uuid | required |
| item_id | uuid | nullable until accepted/corrected if implementation materializes late |
| proposed_name | string | required when provider identifies a thing |
| proposed_category_id | uuid | nullable |
| proposed_quantity | integer | default 1 |
| proposed_fragile | boolean | nullable |
| proposed_tag_ids | uuid[] or join table | optional; from managed tags only |
| confidence_score | decimal | nullable |
| state | enum(`pending`, `auto_accepted`, `accepted`, `corrected`, `needs_correction`, `false_positive`, `conflict`) | required |

Rules:

- Suggestions do not store bounding boxes or crops.
- A false-positive suggestion is excluded from inventory and search.
- A suggestion needing correction may count toward box attention but is not searchable as confirmed inventory.
- No suggestion may overwrite a user-confirmed item without explicit user action.

### 4.12 Item

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| box_id | uuid | required; item is in exactly one box at a time |
| source_media_id | uuid | nullable for manual entries |
| source_recognition_suggestion_id | uuid | nullable |
| name | string | required once confirmed; may be provisional while needing correction |
| category_id | uuid | nullable; managed category |
| quantity | integer | default 1; >1 only for true identicals |
| fragile | boolean | default false; user-editable |
| confidence_score | decimal | nullable |
| created_via | enum(`recognition`, `manual`, `mcp`) | required |
| review_state | enum | see lifecycle |
| presence_state | enum | see lifecycle |

Rules:

- No value amount or value band in Phase 1.
- No bounding box or crop field.
- Tags are attached through a join table from managed tags.
- Manual items have no source media.
- Items needing correction count in item counts but are excluded from normal search until confirmed.

### 4.13 MoveIntegrationToken

| Attribute | Type | Rules |
|-----------|------|-------|
| id | uuid | |
| organization_id | uuid | denormalized for scoping |
| move_id | uuid | required |
| name | string | user-visible label |
| token_digest | string | required; raw token shown only once |
| created_by_user_id | uuid | required |
| revoked_at | timestamp | nullable |
| permissions | jsonb | optional future narrowing; Phase 1 may use fixed tool set |
| last_used_at | timestamp | nullable |

Rules:

- Token is scoped to exactly one Move.
- Token is revocable independently from MoveMembership.
- Token may call mutating MCP tools.
- Audit entries should identify the token/client, source `mcp`, and creating/owning user where relevant.

---

## 5. Lifecycles

### 5.1 Move status

| State | Meaning |
|-------|---------|
| `planned` | Move exists but packing has not started. |
| `started` | Active packing/moving work. |
| `finished` | Move is done but still editable by admins/contributors. |
| `archived` | Read-only historical record. |

### 5.2 Box status

`packing -> sealed -> in_transit -> unpacking -> unpacked`

Rules:

- Admin and contributor can transition box status.
- Sealing requires a room.
- A sealed box can be unsealed.
- Capturing into a sealed box is blocked unless the user unseals it first.
- Recognition results from media captured before sealing may still complete.
- QR scan does not change status.
- Marking a box `unpacked` marks all current in-box items as `removed`.
- Removed items can be restored to `in_box` if marked accidentally.

### 5.3 Media and recognition state

Media upload and recognition are separate concerns:

1. Image upload succeeds.
2. RecognitionRun is created with `queued` status.
3. Job sets `processing`.
4. Provider adapter returns normalized suggestions.
5. Run becomes `succeeded`, `partially_succeeded`, or `failed`.
6. Failed runs can be retried.

No offline capture queue exists in Phase 1.

### 5.4 Item review axis

| State | Meaning |
|-------|---------|
| `pending_review` | Recognition confidence is below threshold; user must keep/correct/mark false detection. |
| `auto_confirmed` | Recognition confidence is at or above Move threshold and no conflict exists. |
| `confirmed` | User confirmed or manually created the item. |
| `needs_correction` | The item or suggestion is known to represent a real item, but its name/category/details need correction. |

There is no `rejected` item state. False detection belongs to `RecognitionSuggestion.state = false_positive`.

### 5.5 Item presence axis

| State | Meaning |
|-------|---------|
| `in_box` | Active inventory in a box. |
| `removed` | Unpacked or taken out of the box. |

Move operation changes `box_id` and keeps `presence_state = in_box`.

---

## 6. Recognition and identification

Recognition is a provider-agnostic identification task.

### 6.1 Provider adapter contract

Domain code talks to a `RecognitionProvider` interface, never directly to a vendor API.

A provider adapter receives:

- Image Media file reference.
- Move vocabulary context: category names, tag names, room/box context where useful.
- Recognition options such as identification granularity.
- Provider selection/configuration, for example `fake`, `openai`, or `anthropic`.

The provider interface returns a provider-independent result object. The normalized minimum object shape mirrors the command-line prototype in `identify_objects.rb`:

```ruby
RecognitionProviders::Result.new(
  provider: "openai",
  provider_model: "gpt-4o",
  objects: [
    RecognitionProviders::DetectedObject.new(
      label: "coffee machine",
      confidence: 0.98,
      count: 1
    )
  ]
)
```

A detected object has these normalized fields:

| Field | Notes |
|-------|-------|
| label | Provider-independent object identity string. Rich labels such as `protein powder bag (Myprotein Impact Whey Isolate)` are allowed and should be preserved as the proposed item name. |
| confidence | Decimal from 0.0 to 1.0. Missing or invalid confidence means the suggestion requires review. |
| count | Integer count. Values greater than 1 are allowed only for interchangeable identical objects. |

The app then maps each detected object into a `RecognitionSuggestion`:

| RecognitionSuggestion field | Source |
|-----------------------------|--------|
| proposed_name | normalized `label` |
| proposed_quantity | normalized `count` |
| confidence_score | normalized `confidence` |
| proposed_category_id | optional app-side resolver using managed Move categories |
| proposed_tag_ids | optional app-side resolver using managed Move tags |
| proposed_fragile | optional app-side inference/provider hint; never authoritative |

OpenAI and Anthropic may return different granularity for the same image. That is expected. The adapter boundary normalizes both into the same `label` / `confidence` / `count` shape before any domain records are created.

No bounding-box data is requested or persisted for Phase 1. If a vendor returns coordinates, the adapter discards them before creating domain records.

### 6.2 Auto-confirm threshold

- Each Move has a static `auto_confirm_threshold`, default 0.8.
- `confidence_score >= threshold` may create an `auto_confirmed` item if no conflict exists.
- `confidence_score < threshold` creates `pending_review`.
- Adaptive per-category thresholds are deferred.

### 6.3 Failure behavior

- If recognition fails, the Media remains attached to the Box.
- Admin/contributor can retry failed recognition.
- Manual item creation is available even if recognition fails.
- A retry creates a new RecognitionRun.

### 6.4 No auto-overwrite

Recognition never overwrites user-confirmed data silently.

If recognition completes after a user manually edited or created similar items from the same media/box context, the system creates a review conflict requiring user resolution.

### 6.5 Merge and quantity rules

Distinct identifiable objects are never collapsed. Quantity > 1 applies only to genuine interchangeable identicals.

---

## 7. Search

Search is Move-scoped and hybrid.

### 7.1 Target behavior

Search ranges over:

- item name;
- category name;
- tag names;
- box number;
- room name;
- source recognition details that have been normalized into item fields.

It must tolerate phrasing mismatches such as `blow dryer` finding `hair dryer`.

### 7.2 Technical target

- PostgreSQL full-text search for lexical matching.
- `pg_trgm` for fuzzy text similarity and misspellings.
- `pgvector` for semantic similarity.
- All queries are scoped to a single Move before results are returned.

### 7.3 Indexing rules

A normalized search document is generated from confirmed item metadata.

Embeddings are generated/refreshed asynchronously after:

- item create/update;
- category rename/remove;
- tag rename/remove;
- box number change;
- room rename/remove;
- item move between boxes.

If embeddings are unavailable, lexical/fuzzy search still works.

### 7.4 Ranking rules

- Exact and strong lexical matches should be boosted above weak semantic matches.
- Semantic matches should recover meaningful synonyms and paraphrases.
- Normal search excludes items in `needs_correction`, false-positive suggestions, and removed items unless the UI explicitly includes removed/uncorrected records.

### 7.5 Privacy

Embeddings are generated only from textual inventory metadata. Raw images are not embedded for Phase 1.

---

## 8. Core domain operations

All write operations live in shared core actions. Web UI and MCP call the same business logic.

| Operation | Notes |
|-----------|-------|
| create_move | creates Move and creator MoveMembership admin |
| manage_move_members | admin only; target user must belong to Organization |
| create_box | generates unique number and permanent QR token |
| update_box | edit number, room, dimensions, weight, tags |
| transition_box_status | admin/contributor; validates lifecycle rules |
| capture_media | image-only Phase 1; requires online upload; queues recognition |
| retry_recognition | admin/contributor; creates a new RecognitionRun |
| add_item_manually | creates confirmed item without media |
| keep_suggestion | accepts suggestion into item |
| correct_suggestion | creates/updates item with user-corrected data |
| mark_false_detection | excludes suggestion from inventory and search |
| edit_item | updates item details; never silently overwritten by recognition |
| move_item | changes box; presence remains `in_box` |
| mark_removed | sets presence to `removed` |
| restore_item_to_box | sets presence to `in_box` |
| search_items | hybrid, Move-scoped |
| manage_categories | admin only |
| manage_tags | admin only |
| manage_rooms | admin only |
| assign_tag/remove_tag | from managed set only |
| resolve_qr | auth-gated; returns box listing without changing status |
| generate_exterior_label | A7 print view; opaque |
| generate_manifest | A4 authenticated view; warn before showing contents |
| create_integration_token | admin only; raw token shown once |
| revoke_integration_token | admin only |

Bulk confirm is intentionally absent.

---

## 9. Permissions

### 9.1 Move roles

| Role | Capabilities |
|------|--------------|
| admin | Full Move control: members, categories, tags, rooms, boxes, items, deletion, restore, integration tokens. |
| contributor | Capture, retry recognition, review, edit, move, remove/restock items, update boxes, transition box status. Cannot manage members or controlled vocabularies. |
| viewer | View and search only. |

### 9.2 Organization boundary

- User must belong to Organization before having a MoveMembership.
- Cross-organization access returns 404 or equivalent non-disclosing failure.
- Move cannot be shared outside Organization.

### 9.3 Archived Move

Archived Move is read-only for all roles except any future explicit unarchive action.

---

## 10. Concurrency and conflicts

The system uses last-action-wins with audit visibility for ordinary concurrent edits.

Examples:

- Two users edit the same item: last save wins, activity feed records both.
- One user moves an item while another marks it removed: last action wins, activity feed records both, restore may be available.
- Two users rename/remove the same tag or room: last action wins if validations pass; activity feed records changes.

Special cases:

- Capturing into a sealed box is blocked until unsealed.
- Recognition completing after user changes may create `RecognitionSuggestion.state = conflict` or item `needs_correction` instead of overwriting confirmed data.
- Server-side validations enforce state transitions even if UI is stale.

---

## 11. Soft delete and restore

User-authored records are soft-deleted by default.

Restore behavior:

- Restoring a parent restores children that were discarded by the same cascade delete action.
- Restore must not resurrect children that had already been independently discarded before the parent deletion.
- Example: deleting a Box discards its Items as part of the same cascade; restoring the Box restores those Items. If an Item had been deleted earlier, restoring the Box does not restore that old deletion.

This rule must be implemented technically with a cascade batch/root marker or equivalent trace.

---

## 12. QR, labels, and manifests

### 12.1 QR

- QR token is permanent for the life of the Box.
- QR token is scoped to the Box.
- QR token is opaque and does not encode contents.
- QR resolves only through an authenticated app route.
- Scanning QR does not change box status.
- Archived Move scan opens read-only listing.

### 12.2 Exterior label

- A7 print target.
- Contains box number, room, and QR only.
- Never contains item names or contents.

### 12.3 Manifest

- A4 authenticated view.
- Warn before displaying/printing because contents are sensitive.
- No public share/export in Phase 1.
- Manifest generation should be auditable if the implementation already audits sensitive read events; otherwise audit can be deferred.

---

## 13. Media retention and privacy

- Source media is retained indefinitely.
- Media access is authorized through Move permissions.
- Storage URLs must not bypass authorization for protected contents.
- Raw images are not used for search embeddings in Phase 1.
- No item value amount or model-suggested value band is stored in Phase 1.

---

## 14. MCP assistant surface

MCP tools are scoped by a MoveIntegrationToken.

Initial tools:

- `search_items`
- `get_box_contents`
- `list_boxes`
- `add_item_to_box`
- `add_media_to_box`
- `move_item`
- `mark_unpacked`
- `get_volume_summary`

Rules:

- Token resolves to one Move and one Organization.
- Token may mutate through the same actions as the web app.
- Token is revocable independently from memberships.
- Source is recorded as `mcp` in audit logs.
- Messaging clients are not in scope.

---

## 15. Deferred decisions

- Video capture and recognition.
- Organization-level room/category/tag templates.
- Monetization and free limits.
- Adaptive confidence thresholds.
- Per-item value/insurance features.
- Manifest PDF generation beyond print view.
- Public sharing or export.
- Weight estimation.
- Long-lived inventory beyond a Move.

---

*End of v0.2.*

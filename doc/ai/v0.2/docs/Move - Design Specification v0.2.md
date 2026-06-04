# Move - Design Specification

**Version:** 0.2.2
**Status:** Updated after product clarification
**For:** Google Stitch in Mobile mode
**Scope:** Feature and screen behavior. This document does not prescribe visual style, layout, or ergonomic details beyond the global direction below.
**Companion:** See `Move - Domain Specification v0.2.md` for entities, lifecycles, and business rules.

---

## 0. Version 0.2 decisions

This version deliberately changes the original v0.1 scope:

- The app is **online-first for Phase 1**. No offline capture, offline edit queue, or offline sync UI is required.
- Recognition is **image-only in Phase 1**. Video-friendly naming such as `media` is allowed, but video capture and recognition are deferred.
- Recognition is provider-agnostic and creates `RecognitionRun` and `RecognitionSuggestion` records.
- No bounding boxes, source crops, crop previews, or crop-highlight UI are part of the product.
- Search is hybrid PostgreSQL search: full-text + `pg_trgm` for lexical/fuzzy matches and `pgvector` for semantic matches.
- A Move belongs to an Organization. Organization tenancy is resolved by subdomain.
- Move roles are exactly **admin**, **contributor**, and **viewer**.
- Categories, rooms, and tags are managed vocabularies scoped to a Move.
- Box has one `room`, not origin and destination room fields.
- Item value fields are out of scope for Phase 1.
- Bulk review actions such as mark-all-reviewed are out of scope.
- Phase 1 is English-only, but all customer/UI-facing strings must come from Rails I18n YAML files.

---

## 1. How to use this with Stitch

- Work in **Mobile** layout mode. Treat responsive desktop layout as later polish.
- Paste the **Global direction** once as standing context.
- Generate one screen at a time from each screen description.
- After screens exist, link them along the flows in the navigation map and use Play to walk the prototype.
- Stitch may choose visual system, typography, spacing, color, component treatment, and navigation pattern.
- The fixed direction is functional: capture, review, search, box clarity, and security must remain fast and obvious.

---

## 2. Global direction

The app should feel **mobile-first, modern, interactive, lightweight, and dark-mode-first**. A light theme is welcome but secondary.

Lightweight means:

- Capturing into the correct box is the fastest action.
- Reviewing uncertain suggestions is glanceable and low-friction.
- Search is always within reach.
- Processing, failed recognition, and permission limits are honest and visible.
- Screens avoid dense forms unless the user explicitly edits details.

The app is not offline-first in Phase 1. When connectivity is missing, the UI should explain that capture and edits require a connection.

---

## 3. Navigation map

**Top-level destinations:** Boxes, Search, Scan, Summary, Menu/Settings.

Let Stitch choose the mobile navigation pattern: tab bar, drawer, floating action, or another suitable pattern.

**Primary flows:**

- **Create account context:** subdomain account -> create/select Move -> Boxes.
- **Pack a box:** Boxes -> Box detail -> Capture image -> Recognition processing -> Review queue -> Box.
- **Find an item:** Search -> result -> Item detail -> its Box.
- **Unpack:** Scan -> Box contents -> mark items removed -> optionally mark box unpacked.
- **Organize:** Menu -> Categories, Tags & Rooms / Members / Settings.
- **Hand to a mover:** Boxes -> Summary -> volume and optional weight.
- **Assistant setup:** Settings -> Assistant / integrations -> create or revoke Move token.

---

## 4. Screens

Each screen lists its purpose, required content, interactions/states, and connections. Visual treatment is open.

### A. Setup and home

#### A1 - Create / select Move

**Purpose:** Pick the active Move within the current Organization subdomain, or start a new one.

**Content:**

- Organization/account name from the current subdomain.
- List of Moves.
- Per Move: name, status, one-line progress hint, box count, pending review count.
- Create-new action.

**Create Move fields:**

- Name.
- Optional planned date.
- Optional origin address.
- Optional destination address.
- Unit system: metric default, imperial optional.

**Move statuses:** planned, started, finished, archived.

**Interactions/states:**

- Empty state when no Moves exist.
- Archived Moves are visibly read-only.
- Creating a Move makes the creator a Move admin.

**Connects to:** Boxes home.

#### A2 - Boxes home

**Purpose:** The main hub for a Move.

**Content:**

- Move name and status.
- List/grid of boxes.
- Per box: number, room, item count, pending review count, and box status.
- Prominent add box action.
- Prominent capture / scan entry.
- Persistent access to Search.
- Compact progress indicator: boxes packed, items pending review, boxes missing dimensions.

**Interactions/states:**

- Empty state when no boxes exist.
- Processing indicators for media currently being recognized.
- Failed recognition indicator with retry entry for admin/contributor.
- Optional filter/sort by room and status.

**Connects to:** Box detail, Capture, Search, Scan, Summary.

---

### B. Box and capture

#### B1 - Box detail

**Purpose:** Everything about one box.

**Content:**

- Box number and status.
- Room.
- Dimensions: length, width, height, derived volume, optional weight.
- Item inventory with pending-review count.
- Media gallery showing full source media thumbnails, not crops.
- Recognition runs and failed/retry state when relevant.
- Actions: capture image, add item manually, review, generate label/QR, seal, unseal, mark in transit, mark unpacking, mark unpacked.

**Interactions/states:**

- Box number is auto-generated and unique per Move, but admin/contributor may override it when creating the box.
- Sealing requires a room.
- A sealed box can be unsealed.
- Capturing into a sealed box is blocked until the user explicitly unseals it.
- Recognition results from media captured before sealing may still complete.
- Archived Move: read-only box listing with no mutating actions.

**Connects to:** Capture, Manual add, Review queue, Item detail, Label & QR, Unpacking mode.

#### B2 - Capture image

**Purpose:** Snap an image of items going into the current box.

**Content:**

- Camera/upload interface.
- Clear indication of which box the capture is going into.
- Shutter/upload action.
- Recent captures for this session.
- Toggle or link to manual add.

**Interactions/states:**

- Phase 1 accepts images only.
- Capture requires connectivity and a successful upload.
- After upload, recognition is queued server-side.
- Media state is visible: uploaded, queued, processing, recognized, failed.
- Failed recognition offers retry for admin/contributor.
- Several captures can be submitted in sequence without leaving the screen.
- No offline queue is required.

**Connects to:** Review queue when recognition creates suggestions, Box detail.

#### B3 - Manual add item

**Purpose:** Add an item without recognition.

**Content:**

- Name.
- Category selection from the managed category set.
- Quantity.
- Fragile toggle.
- Tag selection from the managed tag set.
- Destination box.

**Interactions/states:**

- Lightweight form.
- Category and tag pickers are selection-only.
- Manual item is created as confirmed unless the user leaves required data incomplete.
- No value amount or value band in Phase 1.

**Connects to:** Box detail, Item detail.

---

### C. Review

#### C1 - Review queue

**Purpose:** See all suggestions that need user attention for a box.

**Content:**

- List/grid of recognition suggestions and items needing correction.
- Per entry: proposed name, proposed category, confidence cue, source media thumbnail, and status.
- Visual distinction between auto-confirmed, pending review, needs correction, and failed recognition.
- Entry into item-by-item review.
- Jump to any item or suggestion.

**Interactions/states:**

- Pending review and needs-correction entries appear first.
- No mark-all-reviewed action.
- No bulk confirm action.
- No crop or bounding-box preview.

**Connects to:** Item-by-item review, Item detail, Box detail.

#### C2 - Review item-by-item

**Purpose:** Resolve uncertain recognition suggestions one at a time.

**Content:**

- One suggestion or item at a time.
- Full source media thumbnail or preview.
- Proposed name, category, quantity, tags, fragile flag, and confidence cue.
- Core actions: keep, correct, mark false detection.
- Progress through the queue.

**Interactions/states:**

- Queue is ordered by lowest confidence first.
- Auto-confirmed items are not forced into this flow but remain reachable.
- Keep accepts the suggestion.
- Correct opens edit with proposed data prefilled.
- False detection excludes the suggestion from active inventory and search.
- End-of-queue state returns to Box detail.

**Connects to:** Item detail/edit, Box detail.

#### C3 - Item detail / edit

**Purpose:** View and correct the full record of one item.

**Content:**

- Name.
- Category.
- Quantity.
- Fragile toggle.
- Tags.
- Source media if present, shown as full media, not crop.
- Current box.
- Move to another box.
- Mark as removed / restore to in box.
- Review state and presence state.
- Activity/history entry point.

**Interactions/states:**

- Review and presence are separate state axes.
- Moving an item changes its box; it does not mark it removed.
- Items needing correction count in item counts but do not appear in normal search until confirmed.
- Removed items can be restored to `in_box`.
- Quantity editing is allowed only for genuinely interchangeable identical items.

**Connects to:** Box detail, target box on move, Review queue.

---

### D. Find and organize

#### D1 - Search

**Purpose:** Find any confirmed item in a Move, including years later.

**Content:**

- Single search field.
- Results list showing item, box number, room, and relevant matched metadata.
- Search hint: phrasing does not need to match exactly.

**Interactions/states:**

- Search is scoped to the active Move.
- Search is hybrid: lexical/fuzzy and semantic.
- Empty state with example queries.
- No-results state.
- Embedding/index not-ready states fall back to lexical search.

**Connects to:** Item detail, Box detail.

#### D2 - Categories, tags, and rooms management

**Purpose:** Maintain controlled vocabularies.

**Content:**

- Categories: singular item classification.
- Tags: optional labels applied to items and/or boxes.
- Rooms: box location vocabulary.
- Each list supports add, rename, remove.
- For tags, show applies-to: items, boxes, or both.

**Interactions/states:**

- Admin-only editing.
- Contributor/viewer may select existing values where their role permits editing the target record.
- No free-text category, tag, or room entry in item/box forms.
- Rename updates associated records immediately.
- Remove detaches the value from associated records after confirmation.
- Confirm before removing a value currently in use.

**Connects to:** Box detail, Item detail, Manual add, Settings/Menu.

---

### E. Labels, scanning, and unpacking

#### E1 - Box label and QR

**Purpose:** Produce what goes on or in the box.

**Content:**

- Exterior label preview.
- Exterior label contains only box number, room, and QR.
- No contents on exterior labels.
- Separate option to generate an authenticated detailed manifest.

**Interactions/states:**

- Exterior label target: A7 print view.
- Manifest target: A4 print view; PDF can be a later enhancement.
- Manifest generation warns that contents are sensitive.
- Manifest is authenticated and not shareable publicly.
- No public export/share flow in Phase 1.

**Connects to:** Scan, Box detail.

#### E2 - Scan QR

**Purpose:** Open a box by scanning its label.

**Content:**

- Scanner view.
- Authenticated resolution state.
- Unrecognized/foreign QR state.
- Read-only archived state.

**Interactions/states:**

- QR token resolves only through the app.
- User must be authenticated and have Move access.
- Scan opens the box contents listing.
- Scan does not change box status.
- Admin/contributor see edit/unpack actions when allowed.
- Viewer sees read-only contents.

**Connects to:** Box detail / Box contents / Unpacking mode.

#### E3 - Unpacking mode

**Purpose:** Work through a box at the destination.

**Content:**

- Box items as a checklist.
- Quick mark removed.
- Remaining count.
- Mark box unpacked action.

**Interactions/states:**

- Removed items visibly settle out of the active list.
- Marking a box unpacked marks all items as removed.
- Removed items can be restored to in box.
- Archived Move remains read-only.

**Connects to:** Box detail, Item detail.

---

### F. Collaboration and insight

#### F1 - Members and roles

**Purpose:** Manage who can do what on a Move.

**Content:**

- Member list.
- Roles: admin, contributor, viewer.
- Invite action for Organization users.
- Role change action.

**Interactions/states:**

- Admin-only.
- Explain each role briefly.
- A Move cannot be shared with someone outside the Organization.
- If an invite creates a new user, it must also add them to the Organization before adding the MoveMembership.
- Concurrent changes use last-action-wins plus activity feed visibility and restore where applicable.

**Connects to:** Settings/Menu.

#### F2 - Volume and weight summary

**Purpose:** The mover-facing picture.

**Content:**

- Total volume.
- Optional total weight.
- Breakdown per room and per Move.
- Box count.
- Missing dimension warnings.

**Interactions/states:**

- Respect Move unit system.
- Dimensions and weight use canonical measurement storage and display conversion.
- Boxes missing dimensions are flagged so totals are honest.
- Export/share is optional and not required in Phase 1.

**Connects to:** Box detail.

#### F3 - Settings / menu

**Purpose:** App-level and Move-level controls.

**Content:**

- Theme, dark mode default.
- Move unit system.
- Static auto-confirm confidence threshold, default 0.8.
- Assistant / integrations area to create and revoke per-Move MCP integration tokens.
- Account settings.

**Interactions/states:**

- Changing threshold previews effect in plain terms: more review vs more hands-free.
- Threshold is static in Phase 1. No adaptive per-category threshold.
- Messaging channels such as Telegram or WhatsApp are out of scope for the web app.

**Connects to:** Everywhere through menu.

---

## 5. Cross-cutting patterns

Apply these consistently across screens.

- **Online-first honesty.** Capture and edits require connectivity in Phase 1. No offline mutation queue.
- **Recognition states.** Media and recognition runs move through queued, processing, succeeded, failed, and retry states. Surface this without blocking further work.
- **Confidence cues.** Auto-confirmed, pending review, and needs-correction states must be visually distinct.
- **Two-axis item state.** Review state and presence state are independent. Moved means box changed, not removed.
- **No crops or bounding boxes.** Review and item detail show full source media only.
- **Security by default.** QR and manifests never reveal contents without authentication.
- **Empty, loading, error states.** Every list needs a considered state.
- **Dark mode.** Default theme.

---

## 6. Areas needing design attention

1. **Review experience.** Keep/correct/false-detection flow must feel fast without bulk shortcuts.
2. **Capture-to-box clarity.** Users must never wonder which box receives the image.
3. **Processing state.** Recognition can be queued or failed; this must be obvious but calm.
4. **Search trust.** Semantic results should still explain which box and room make the result useful.
5. **Security-sensitive label flow.** Exterior labels are opaque; manifests are authenticated and warned.
6. **Dimensions entry.** L x W x H must feel optional-but-easy; summary must flag missing dimensions.
7. **Quantity merge/split.** Only true identicals should become quantity > 1.
8. **Feature density.** The app has many capabilities; mobile navigation must remain sparse and fast.

---

*End of v0.2.*

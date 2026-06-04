# Phase 04 - Items Media and Manual Inventory

## Goal

Add item inventory, image media upload, manual item creation, and item movement/removal behavior.

By the end of this phase, users can manually add items to boxes, attach image media to boxes, move items between boxes, mark items removed, and view a media gallery.

## Depends on

- Phase 03 complete.

## Out of scope

- Recognition provider processing.
- RecognitionSuggestion review.
- Hybrid search.
- QR scan/labels/manifests.
- MCP tools.
- Offline capture queue.
- Bounding boxes/crops.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Create Media model with Active Storage attachment.
2. Accept image uploads only in Phase 1.
3. Create Item model.
4. Add item tags join table.
5. Add manual item creation action.
6. Add item edit action.
7. Add item move action.
8. Add mark removed and restore to box actions.
9. Add item detail/edit UI.
10. Add manual add UI.
11. Add media gallery on box detail using full media thumbnails.
12. Add capture image UI that uploads media and records it, but does not yet run recognition.
13. Block capture into sealed boxes unless unsealed first.
14. Add retention policy note or code path ensuring media is not auto-purged.

## Data model

### media

- `organization_id`
- `move_id`
- `box_id`
- `media_type`, Phase 1 only `image`
- `captured_at`
- `captured_via`: `web` or `mcp`
- Active Storage attachment

### items

- `organization_id`
- `move_id`
- `box_id`
- `source_media_id`, nullable
- `source_recognition_suggestion_id`, nullable for future phase
- `name`
- `category_id`, nullable
- `quantity`, default 1
- `fragile`, default false
- `confidence_score`, nullable
- `created_via`: `manual`, future `recognition`, future `mcp`
- `review_state`: manual items start `confirmed`
- `presence_state`: default `in_box`

No `value_amount`, `value_band`, `bounding_box`, `crop`, or `source_frame_ref` fields.

## UI

- Manual add form.
- Item detail/edit.
- Item list on box detail.
- Media gallery on box detail.
- Capture/upload image into current box.
- Stale sealed box warning and unseal prompt.

## Events

- `media.captured`
- `item.created`
- `item.updated`
- `item.moved`
- `item.removed`
- `item.restored_to_box`

## Tests

- Admin/contributor can upload image media to packing box.
- Viewer cannot upload.
- Capture into sealed box is blocked.
- Manual item creation requires allowed role.
- Manual item uses managed category and tags only.
- Item move changes box and keeps `presence_state = in_box`.
- Mark removed changes presence to `removed`.
- Restore to box changes presence to `in_box`.
- Media and items are tenant/move scoped.
- No crop/bounding-box columns exist.

## Runtime verification

- Create a box.
- Upload an image.
- See it in the media gallery.
- Add manual item.
- Edit item details.
- Move item to another box.
- Mark item removed and restore it.
- Seal box and confirm capture is blocked unless unsealed.

## Acceptance criteria

- Manual inventory works end to end.
- Media upload and gallery work without recognition.
- Domain contains no offline queue and no crop/bounding-box data.
- System is ready for recognition pipeline.

## Suggested issue title

`Phase 04: Add items, media upload, and manual inventory`

## Suggested branch

`feature/phase-04-items-media`

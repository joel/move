# Phase 05 - Recognition Pipeline

## Goal

Add provider-agnostic image recognition with RecognitionRun and RecognitionSuggestion.

By the end of this phase, captured images can be queued, processed through a provider adapter, produce normalized suggestions, fail safely, and be retried.

## Depends on

- Phase 04 complete.

## Out of scope

- Hybrid search implementation, except enqueueing future indexing hooks if useful.
- Final review UX polish beyond basic suggestion listing.
- Video recognition.
- Bounding boxes/crops.
- Raw vendor response persistence.
- Offline recognition queue beyond normal server-side jobs.

## Main tasks

1. Create RecognitionRun model.
2. Create RecognitionSuggestion model.
3. Add provider-agnostic RecognitionProvider interface.
4. Add normalized provider result objects: `Result(provider, provider_model, objects)` and `DetectedObject(label, confidence, count)`.
5. Add deterministic fake provider for tests/development.
6. Add OpenAI and Anthropic adapter classes shaped around the `identify_objects.rb` prototype.
7. Add provider selection through environment/configuration, for example `RECOGNITION_PROVIDER=openai|anthropic|fake`.
8. Add RecognitionRuns::Enqueue action called after image media capture.
9. Add RecognitionRuns::Process job using Solid Queue.
10. Add provider context from Move vocabularies: categories and tags.
11. Persist normalized suggestions only.
12. Discard bounding box data if provider returns it.
13. Implement static threshold behavior from Move `auto_confirm_threshold`.
14. Materialize auto-confirmed items when confidence is high and no conflict exists.
15. Create pending suggestions/items when confidence is below threshold.
16. Add failed/partial/succeeded states and retry action.
17. Add basic UI indicators on box detail and media gallery.
18. Keep all new customer/UI-facing strings in YAML I18n files.

## Data model

### recognition_runs

- `organization_id`
- `move_id`
- `box_id`
- `media_id`
- `provider`
- `provider_model`
- `status`: `queued`, `processing`, `succeeded`, `failed`, `partially_succeeded`
- `error_code`
- `error_message`
- `metadata`, provider-independent and redacted
- `started_at`
- `completed_at`

### recognition_suggestions

- `organization_id`
- `move_id`
- `box_id`
- `media_id`
- `recognition_run_id`
- `item_id`, nullable
- `proposed_name`
- `proposed_category_id`
- `proposed_quantity`
- `proposed_fragile`
- `confidence_score`
- `state`: `pending`, `auto_accepted`, `accepted`, `corrected`, `needs_correction`, `false_positive`, `conflict`

Suggested tags may use a join table or normalized JSON of tag ids, but must resolve only to managed tags.

No `raw_response`, `bounding_box`, `crop`, or vendor payload columns.

## Provider contract

The app calls a provider interface and receives normalized provider-independent result objects.

Suggested Ruby shape:

```ruby
module RecognitionProviders
  DetectedObject = Data.define(:label, :confidence, :count)
  Result = Data.define(:provider, :provider_model, :objects)

  class Base
    def identify(image:, context:)
      # returns Result
    end
  end
end
```

The `identify_objects.rb` prototype is the reference shape for provider adapters. Both OpenAI and Anthropic adapters must normalize their output to a strict object array:

```json
[
  {"label":"coffee machine","confidence":0.98,"count":1},
  {"label":"fruit","confidence":0.93,"count":3}
]
```

Normalized object fields:

- `label`: specific object identity string; preserve rich names such as `protein powder bag (Myprotein Impact Whey Isolate)`.
- `confidence`: decimal between 0.0 and 1.0.
- `count`: integer count.

The application maps normalized objects to RecognitionSuggestions:

- `label` -> `proposed_name`;
- `count` -> `proposed_quantity`;
- `confidence` -> `confidence_score`;
- managed category/tag suggestions may be resolved app-side using Move vocabularies.

Any vendor-specific details stay inside the adapter and sanitized operational logs, not domain tables. Raw provider responses must not be persisted.

## Threshold rules

- Confidence >= Move threshold creates auto-confirmed item if no conflict.
- Confidence < threshold creates pending review suggestion/item.
- Missing confidence defaults to pending review.
- Threshold is static per Move in Phase 1.

## Failure rules

- Failed run does not delete media.
- Failed run can be retried by admin/contributor.
- Retry creates a new run.
- Manual item creation remains available.
- Job failures must not leave `processing` forever.

## Events

- `recognition_run.queued`
- `recognition_run.started`
- `recognition_run.succeeded`
- `recognition_run.partially_succeeded`
- `recognition_run.failed`
- `recognition_run.retried`
- `recognition_suggestion.created`
- `recognition_suggestion.auto_accepted`

## Tests

- Capture creates media and enqueues RecognitionRun.
- Process job restores Current context.
- Fake provider creates deterministic suggestions.
- High-confidence suggestion creates auto-confirmed item.
- Low-confidence suggestion creates pending review.
- Failed provider marks run failed with sanitized error.
- Retry creates new run.
- No raw provider response stored.
- No bounding box/crop stored even if fake provider returns coordinates.
- OpenAI/Anthropic adapter parser accepts prototype JSON shape and normalizes to `label` / `confidence` / `count`.
- Invalid JSON from provider marks the run failed with sanitized error.
- Customer/UI-facing recognition states and errors render through I18n keys.
- Sealed box can receive results for media captured before sealing.
- Recognition does not overwrite existing confirmed user item.

## Runtime verification

- Upload image to packing box.
- See recognition queued.
- Run job and see processing/succeeded.
- See auto-confirmed item.
- See pending review suggestion.
- Force provider failure and retry.
- Confirm source media remains available.

## Acceptance criteria

- Recognition pipeline exists end to end with fake provider.
- Production provider can be added by adapter without schema change.
- No vendor-specific schema leakage exists in domain tables.
- No crop/bounding-box behavior exists.

## Suggested issue title

`Phase 05: Add provider-agnostic image recognition pipeline`

## Suggested branch

`feature/phase-05-recognition`

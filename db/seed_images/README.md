# Seed images

Realistic, 1:1 demo photos for the showcase Move in `db/seeds.rb`. One JPEG per
`SeedData::PHOTOS` entry, named `<slug>.jpg`. These are **committed** so
`db:seed` shows real photographs offline, on a fresh DB, and in CI.

## How they're produced

They are generated **once** (not at seed time — `db:seed` must stay offline and
deterministic) by the OpenAI Images API via a rake task, then committed:

```bash
# One-off, needs an API key and network. Generates only missing slugs.
OPENAI_API_KEY=sk-… bin/rails seed_images:generate

# Regenerate everything (overwrite existing):
OPENAI_API_KEY=sk-… FORCE=1 bin/rails seed_images:generate

# Optional overrides:
#   SEED_IMAGE_MODEL=gpt-image-1   SEED_IMAGE_SIZE=1024x1024   SEED_IMAGE_QUALITY=medium
```

Each image is downscaled to a 512px long edge and saved as a small stripped JPEG
(~30–80 KB). Cost is roughly $0.04/image (≈ a dollar for the full set).

## Recognition is recorded too (record / replay)

The demo's item *detections* are also a recorded artifact, not hand-authored.
After the images exist, a second one-off task runs the **real** recognition
pipeline (OpenAI `gpt-5-mini`) over each photo and records what it detects into
`db/seed_data/recognition/<slug>.json`. `db:seed` replays those, so reseeding the
same dataset **never re-pays for vision tokens**:

```bash
OPENAI_API_KEY=sk-… bin/rails seed_recognition:record   # needs the images first
```

`review_state` is derived on replay from each detection's confidence vs the
Move's `auto_confirm_threshold` (≥ → `auto_confirmed`, else `pending_review`),
exactly like `RecognitionRuns::Process`. The authored `items:` in the catalog
stay as the **offline fallback** when a slug has no recording yet. The synthetic
showcase states the model can't produce — `needs_correction`, the failed/empty
recovery tiles, the manual (no-photo) items — remain authored in the catalog.

## Refresh both artifacts at once

```bash
OPENAI_API_KEY=sk-… bin/rails seed_data:refresh   # images, then recognition
```

## Workflow

1. Edit `db/seed_data/catalog.rb` (add/adjust a `PHOTOS` entry with a `slug` +
   `prompt`, and authored fallback `items:`).
2. Run `seed_data:refresh` (or the two tasks individually), review the JPEGs here
   and the JSON in `db/seed_data/recognition/`, then commit both.
3. Re-seed:
   - On a **fresh** DB (`bin/reset`), items show the real photos **and** the
     real recorded detections.
   - On an **already-seeded** tenant, a plain `bin/rails db:seed` upgrades the
     photo *blobs* in place (placeholder → real JPEG), but swapping the
     *detection content* (authored fallback → recorded, or changed recordings)
     needs a from-scratch reseed (`bin/reset`) — re-materializing recognition on
     an existing tenant would discard any review edits, so it's intentionally
     reset-only. The canonical refresh flow is therefore: refresh artifacts →
     commit → `bin/reset`.

Until a slug's JPEG exists here, `db:seed` falls back to `public/icon.png` for
that photo; until its recognition JSON exists, it falls back to the authored
`items:` — so seeding never breaks on a missing artifact.

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

## Workflow

1. Edit `db/seed_data/catalog.rb` (add/adjust a `PHOTOS` entry with a `slug` +
   `prompt`).
2. Run `seed_images:generate`, review the JPEGs here, then commit them.
3. `bin/rails db:seed` — items light up with their real photos.

Until a slug's JPEG exists here, `db:seed` falls back to `public/icon.png` for
that photo, so seeding never breaks on a missing image.

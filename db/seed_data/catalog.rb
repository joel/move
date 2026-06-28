# frozen_string_literal: true

require "json"

# Demo catalog for the "Seattle Relocation" showcase Move (db/seeds.rb).
#
# This is the single source of truth for the demo's boxes, photos and items. Two
# consumers read it, so they never drift:
#
#   1. db/seeds.rb            — builds the records (offline, deterministic).
#   2. lib/tasks/seed_images  — generates one real photo per PHOTOS entry via the
#      OpenAI Images API (`seed_images:generate`) into db/seed_images/<slug>.jpg.
#
# A PHOTOS entry's `slug` names its generated image AND its idempotency: the seed
# attaches db/seed_images/<slug>.jpg when present, else falls back to the
# placeholder icon — so `db:seed` works on a fresh DB / CI with no images, and
# lights up with real photos once they're generated and committed.
#
# Vocabulary references (category/tags) MUST match Moves::DefaultVocabularies
# (+ the demo-only "Everyday Use" tag). Fragility is a box-level flag now
# (BOXES `fragile:`, a manual mark that prints FRAGILE on the label), not an item
# attribute or tag. Guarded by spec/seed_data/catalog_spec.rb.
module SeedData
  # number => box. dims: [length_cm, width_cm, height_cm, weight_kg] (nil ok).
  # Covers every lifecycle state, full/partial/no dimensions, a roomless box (the
  # seal-requires-room guard), repeated sizes (the "Reuse dimensions" chips:
  # 40x30x25 thrice, 60x40x40 twice), with/without a description, and two boxes
  # marked `fragile` (10, 13) so the FRAGILE chip + printed label are showcased.
  BOXES = [
    { number: "1",  room: "Kitchen",     status: "sealed",     dims: [40, 30, 25, 8],
      desc: "Cookware, small appliances, heavy utensils. Keep upright." },
    { number: "2",  room: "Kitchen",     status: "packing",    dims: [] },
    { number: "3",  room: "Living Room", status: "sealed",     dims: [60, 40, 40, 15],
      desc: "Books, framed photos, throw blankets." },
    { number: "4",  room: "Bedroom",     status: "packing",    dims: [50, 40, nil, 6] },
    { number: "5",  room: "Garage",      status: "in_transit", dims: [80, 60, 50, 22],
      desc: "Power tools, extension cords, hardware." },
    { number: "6",  room: nil,           status: "packing",    dims: [] },
    { number: "7",  room: "Bedroom",     status: "unpacking",  dims: [55, 45, 35, 12] },
    { number: "8",  room: "Living Room", status: "unpacked",   dims: [60, 40, 40, 14] },
    { number: "9",  room: "Kitchen",     status: "packing",    dims: [40, 30, 25, 7] },
    { number: "10", room: "Kitchen",     status: "sealed",     dims: [40, 30, 25, 9], fragile: true,
      desc: "Glassware and seasonal dishes." },
    { number: "11", room: "Office",      status: "packing",    dims: [45, 35, 30, 9] },
    { number: "12", room: "Bathroom",    status: "sealed",     dims: [35, 25, 25, 5],
      desc: "Towels, toiletries, daily essentials." },
    { number: "13", room: "Dining Room", status: "in_transit", dims: [55, 45, 30, 11], fragile: true,
      desc: "Dinnerware and glassware — fragile, pack with care." },
    { number: "14", room: "Garage",      status: "packing",    dims: [70, 50, 40, 13],
      desc: "Camping and outdoor gear." },
    { number: "15", room: "Living Room", status: "sealed",     dims: [60, 40, 40, 13],
      desc: "Game console, board games and media." }
  ].freeze

  # Photos (→ one Media + one generated image each), grouped onto a box by number.
  # `status`:
  #   "succeeded" — recognition run succeeded; `items` are materialised (Items
  #                 linked to this photo via source_media).
  #   "empty"     — run succeeded with zero detections (orphaned photo → recovery
  #                 tile). No items.
  #   "failed"    — run failed (orphaned photo → recovery tile). No items; carries
  #                 `error_code`/`error_message`.
  # `captured_at`: seconds ago, so the per-photo review walk (box 1) visits photos
  #   in this listed order (larger = earlier = visited first).
  # An item: name (required), confidence, review, presence (default "in_box"),
  #   category, tags.
  PHOTOS = [
    # --- Box 1: the review-walk showcase (3 scene photos + 2 recovery tiles) ----
    { box: "1", slug: "kitchen-counter", status: "succeeded", captured_at: 300,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a kitchen counter holding a " \
              "stainless-steel drip coffee maker, a short stack of hardcover " \
              "books, and a set of four ceramic mugs. Even daylight, eye-level, " \
              "mild clutter, no text or watermarks.",
      items: [
        { name: "Coffee maker", confidence: 0.97, review: "auto_confirmed", category: "Appliances" },
        { name: "Stack of books", confidence: 0.88, review: "auto_confirmed", category: "Books", tags: ["Heavy"] },
        { name: "Set of mugs",   confidence: 0.62, review: "pending_review", category: "Kitchenware" },
        { name: "Table lamp",    confidence: 0.55, review: "pending_review", category: "Electronics" },
        { name: "Picture frame", confidence: 0.41, review: "pending_review", category: "Decor" }
      ] },
    { box: "1", slug: "open-shelving", status: "succeeded", captured_at: 240,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of open wall shelving with a folded " \
              "throw blanket, a decorative ceramic vase, a framed piece of wall " \
              "art, and a stack of glossy magazines. Even daylight, eye-level, " \
              "no text or watermarks.",
      items: [
        { name: "Throw blanket",   confidence: 0.68, review: "pending_review", category: "Decor" },
        { name: "Decorative vase", confidence: 0.47, review: "pending_review", category: "Decor" },
        { name: "Wall art",       confidence: 0.53, review: "pending_review", category: "Decor" },
        { name: "Bookshelf",      confidence: 0.44, review: "pending_review", category: "Furniture" },
        { name: "Magazines",      confidence: 0.58, review: "needs_correction", category: "Books" }
      ] },
    { box: "1", slug: "floor-corner", status: "succeeded", captured_at: 180,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a living-room floor corner with a " \
              "rolled area rug, a tall floor lamp, a small wooden coffee table, " \
              "and a ceramic floor vase. Even daylight, eye-level, no text.",
      items: [
        { name: "Area rug",    confidence: 0.58, review: "pending_review", category: "Decor" },
        { name: "Floor lamp",  confidence: 0.62, review: "pending_review", category: "Electronics" },
        { name: "Coffee table", confidence: 0.52, review: "pending_review", category: "Furniture" },
        { name: "Floor vase",  confidence: 0.51, review: "pending_review", category: "Decor" },
        { name: "Wall clock",  confidence: 0.54, review: "pending_review", category: "Decor" }
      ] },
    { box: "1", slug: "recovery-failed", status: "failed", captured_at: 30,
      provider: "openai", provider_model: "gpt-5-mini",
      error_code: "ProviderHttp::Error",
      error_message: "RecognitionProviders::Openai request failed (429): " \
                     "You exceeded your current quota, please check your plan and billing details.",
      prompt: "A slightly dim, slightly blurry smartphone snapshot of a cluttered " \
              "shelf corner in low indoor light, hard to make out. No text.",
      items: [] },
    { box: "1", slug: "recovery-empty", status: "empty", captured_at: 20,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an empty cardboard moving box " \
              "interior, plain brown, nothing inside. Even light, no text.",
      items: [] },

    # --- Box 3 (Living Room, sealed): gallery contents -------------------------
    { box: "3", slug: "living-room-shelf", status: "succeeded", captured_at: 600,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a living-room shelf with a row of " \
              "hardcover books, two framed family photos, a folded wool blanket, " \
              "and a small stack of vinyl records. Even daylight, no text.",
      items: [
        { name: "Hardcover Books", confidence: 0.90, review: "auto_confirmed", category: "Books", tags: ["Heavy"] },
        { name: "Framed Photos",  confidence: 0.85, review: "auto_confirmed", category: "Decor",
          tags: ["Important"] },
        { name: "Wool Blanket",   confidence: 0.70, review: "confirmed", category: "Clothing" },
        { name: "Vinyl Records",  confidence: 0.60, review: "pending_review", category: "Decor", tags: ["Valuable"] }
      ] },

    # --- Box 5 (Garage, in_transit): power tools -------------------------------
    { box: "5", slug: "garage-power-tools", status: "succeeded", captured_at: 600,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a workbench with a cordless power " \
              "drill, a coiled orange extension cord, a socket wrench set in a " \
              "case, and safety goggles. Even daylight, eye-level, no text.",
      items: [
        { name: "Cordless Drill", confidence: 0.92, review: "auto_confirmed", category: "Tools", tags: ["Heavy"] },
        { name: "Extension Cord", confidence: 0.80, review: "auto_confirmed", category: "Tools" },
        { name: "Socket Set", confidence: 0.70, review: "confirmed", category: "Tools", tags: ["Heavy"] },
        { name: "Safety Goggles", confidence: 0.60, review: "pending_review", category: "Tools" }
      ] },

    # --- Box 7 (Bedroom, unpacking): removal demo — items already unpacked -----
    # presence at the photo level (applied to every item) so the box-7 removal
    # demo keeps its "all already unpacked" state even when recorded recognition
    # replaces the authored item names. Default is "in_box".
    { box: "7", slug: "bedside-shelf", status: "succeeded", captured_at: 120, presence: "removed",
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a bedside shelf with a phone " \
              "charger and cable, and a paperback novel. Even indoor light, no text.",
      items: [
        { name: "Phone Charger", confidence: 0.90, review: "confirmed",
          category: "Electronics", tags: ["Everyday Use"] },
        { name: "Paperback", confidence: 0.90, review: "confirmed", category: "Books" }
      ] },

    # --- Box 9 (Kitchen, packing): removal demo — one photo, two in-box items --
    { box: "9", slug: "skillet-and-bowls", status: "succeeded", captured_at: 120,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a kitchen counter with a black " \
              "cast-iron skillet and a nested set of stainless mixing bowls. " \
              "Even daylight, eye-level, no text.",
      items: [
        { name: "Cast Iron Skillet", confidence: 0.90, review: "confirmed", category: "Kitchenware", tags: ["Heavy"] },
        { name: "Mixing Bowls",     confidence: 0.90, review: "confirmed", category: "Kitchenware" }
      ] },

    # --- Box 11 (Office, packing): desk gear -----------------------------------
    { box: "11", slug: "office-desk", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an office desk with a closed " \
              "laptop, an external monitor, a mechanical keyboard, a desk lamp, " \
              "and a stack of notebooks. Even daylight, eye-level, no text.",
      items: [
        { name: "Laptop",           confidence: 0.95, review: "auto_confirmed", category: "Electronics",
          tags: %w[Valuable Important] },
        { name: "External Monitor", confidence: 0.88, review: "auto_confirmed", category: "Electronics" },
        { name: "Mechanical Keyboard", confidence: 0.70, review: "confirmed", category: "Electronics" },
        { name: "Desk Lamp",        confidence: 0.60, review: "pending_review", category: "Electronics" },
        { name: "Notebook Stack",   confidence: 0.50, review: "pending_review", category: "Documents" }
      ] },

    # --- Box 12 (Bathroom, sealed): toiletries ---------------------------------
    { box: "12", slug: "bathroom-counter", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a bathroom counter with folded " \
              "bath towels, a zipped toiletry bag, an electric toothbrush on its " \
              "charger, and a pump bottle of hand soap. Even light, no text.",
      items: [
        { name: "Bath Towels",       confidence: 0.85, review: "auto_confirmed", category: "Clothing" },
        { name: "Toiletry Bag",      confidence: 0.70, review: "confirmed", category: "Clothing",
          tags: ["Everyday Use"] },
        { name: "Electric Toothbrush", confidence: 0.60, review: "pending_review", category: "Electronics",
          tags: ["Everyday Use"] },
        { name: "Hand Soap", confidence: 0.50, review: "pending_review", category: "Kitchenware",
          tags: ["Liquid"] }
      ] },

    # --- Box 13 (Dining Room, in_transit): fragile dinnerware ------------------
    { box: "13", slug: "dining-ware", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a dining table with a stack of " \
              "white dinner plates, a row of stemmed wine glasses, a large " \
              "serving bowl, and a folded linen tablecloth. Even daylight, no text.",
      items: [
        { name: "Dinner Plates", confidence: 0.90, review: "auto_confirmed", category: "Kitchenware" },
        { name: "Wine Glasses",  confidence: 0.85, review: "auto_confirmed", category: "Kitchenware",
          tags: ["Valuable"] },
        { name: "Serving Bowl",  confidence: 0.70, review: "confirmed", category: "Kitchenware" },
        { name: "Linen Tablecloth", confidence: 0.60, review: "pending_review", category: "Clothing" }
      ] },

    # --- Box 14 (Garage, packing): camping gear --------------------------------
    { box: "14", slug: "camping-gear", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of camping gear on a garage floor: a " \
              "packed dome tent in its bag, a rolled sleeping bag, a bicycle " \
              "helmet, and a hand air pump. Even daylight, no text.",
      items: [
        { name: "Camping Tent",  confidence: 0.80, review: "confirmed", category: "Toys",
          tags: %w[Seasonal Heavy] },
        { name: "Sleeping Bag",  confidence: 0.70, review: "confirmed", category: "Clothing", tags: ["Seasonal"] },
        { name: "Bicycle Helmet", confidence: 0.60, review: "pending_review", category: "Toys" },
        { name: "Hand Pump", confidence: 0.50, review: "pending_review", category: "Tools" }
      ] },

    # --- Box 15 (Living Room, sealed): entertainment ---------------------------
    { box: "15", slug: "entertainment-unit", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an entertainment unit with a game " \
              "console, a stack of boxed board games, a streaming remote, and a " \
              "row of DVD cases. Even daylight, eye-level, no text.",
      items: [
        { name: "Game Console",    confidence: 0.90, review: "auto_confirmed", category: "Electronics",
          tags: ["Valuable"] },
        { name: "Board Games",     confidence: 0.70, review: "confirmed", category: "Toys" },
        { name: "DVD Collection",  confidence: 0.60, review: "pending_review", category: "Decor" },
        { name: "Streaming Remote", confidence: 0.50, review: "pending_review", category: "Electronics" }
      ] }
  ].freeze

  # Manual items with NO photo (created_via: "manual"). Keyed on name within a box
  # so re-running never duplicates. Spans the review axis (confirmed /
  # needs_correction) and the presence axis (in_box / removed). The box-5 "Hair
  # dryer" backs the semantic-search demo ("blow dryer" ~ "Hair dryer").
  MANUAL_ITEMS = [
    { box: "2", name: "Espresso Machine",
      category: "Electronics", tags: ["Heavy"], review: "confirmed", presence: "in_box" },
    { box: "2", name: "Dinner Plates",
      category: "Kitchenware", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    { box: "4", name: "Paperback Novels",
      category: "Books", tags: ["Heavy"], review: "needs_correction", presence: "in_box" },
    { box: "4", name: "Winter Coat",
      category: "Clothing", tags: ["Seasonal"], review: "confirmed", presence: "removed" },
    { box: "5", name: "Hair dryer",
      category: "Electronics", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Bedside Lamp",
      category: "Electronics", tags: ["Important"], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Folded Bedsheets",
      category: "Clothing", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Alarm Clock",
      category: "Electronics", tags: [], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Throw Pillows",
      category: "Clothing", tags: [], review: "confirmed", presence: "removed" },
    { box: "7", name: "Reading Glasses",
      category: nil, tags: ["Important"], review: "confirmed", presence: "removed" }
  ].freeze

  # --- Recognition record/replay --------------------------------------------
  # The expensive vision-recognition output is recorded ONCE from a real run
  # (`rails seed_recognition:record`, OpenAI gpt-image-1's sibling gpt-5-mini)
  # into db/seed_data/recognition/<slug>.json, committed, and replayed by the
  # seed — so reseeding the same dataset never re-pays for tokens. The authored
  # `items:` above stay as the offline fallback when no recording exists yet.

  # The recorded recognition objects for a photo slug, or nil when none committed.
  def self.recorded_recognition(slug)
    path = File.join(__dir__, "recognition", "#{slug}.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError
    nil
  end

  # The detections to seed for a succeeded photo: the recorded REAL recognition
  # objects when present (review_state derived from confidence vs `threshold`,
  # mirroring RecognitionRuns::Process), else the authored catalog items
  # (explicit review_state) as the offline fallback. Uniform hash shape either
  # way: { name:, confidence:, category:, tags:, review: }.
  def self.detections_for(photo, threshold:)
    recorded = recorded_recognition(photo[:slug])
    return normalize_recorded(recorded["objects"], threshold: threshold) if recorded

    Array(photo[:items]).map { |item| authored_detection(item) }
  end

  # Normalize recorded provider objects into the uniform detection shape, with
  # review_state split on the auto-confirm threshold (the pipeline's rule). Drops
  # blank labels.
  def self.normalize_recorded(objects, threshold:)
    Array(objects).filter_map { |object| recorded_detection(object, threshold: threshold) }
  end

  def self.recorded_detection(object, threshold:)
    label = object["label"].to_s.strip
    return nil if label.empty?

    confidence = object["confidence"]&.to_f
    {
      name: label,
      confidence: confidence,
      category: object["category"].to_s.strip.presence,
      tags: Array(object["tags"]).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq,
      review: confidence && confidence >= threshold ? "auto_confirmed" : "pending_review"
    }
  end

  def self.authored_detection(item)
    {
      name: item[:name], confidence: item[:confidence],
      category: item[:category], tags: item[:tags] || [], review: item[:review]
    }
  end
end

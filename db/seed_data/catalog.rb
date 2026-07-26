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
# Room references (BOXES `room:`) MUST match Moves::DefaultVocabularies::ROOMS.
# An item is just a name now — category, tags, quantity and fragility were all
# removed across the simplification epic (fragility moved to BOXES `fragile:`).
# Guarded by spec/seed_data/catalog_spec.rb.
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
  # `pending_floor`: at least N of this photo's detections seed unreviewed, even
  #   when a recorded recognition would auto-confirm everything (see
  #   apply_pending_floor). Declared on photos in TWO boxes (1 and 11, distinct
  #   captured_at) so the Move-wide review queue and its cross-box "Review all"
  #   walk (#654) are demoable from a fresh seed (#656).
  # An item: name (required), confidence, review, presence (default "in_box").
  PHOTOS = [
    # --- Box 1: the review-walk showcase (3 scene photos + 2 recovery tiles) ----
    { box: "1", slug: "kitchen-counter", status: "succeeded", captured_at: 300, pending_floor: 2,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a kitchen counter holding a " \
              "stainless-steel drip coffee maker, a short stack of hardcover " \
              "books, and a set of four ceramic mugs. Even daylight, eye-level, " \
              "mild clutter, no text or watermarks.",
      items: [
        { name: "Coffee maker", confidence: 0.97, review: "auto_confirmed" },
        { name: "Stack of books", confidence: 0.88, review: "auto_confirmed" },
        { name: "Set of mugs",   confidence: 0.62, review: "pending_review" },
        { name: "Table lamp",    confidence: 0.55, review: "pending_review" },
        { name: "Picture frame", confidence: 0.41, review: "pending_review" }
      ] },
    { box: "1", slug: "open-shelving", status: "succeeded", captured_at: 240,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of open wall shelving with a folded " \
              "throw blanket, a decorative ceramic vase, a framed piece of wall " \
              "art, and a stack of glossy magazines. Even daylight, eye-level, " \
              "no text or watermarks.",
      items: [
        { name: "Throw blanket",   confidence: 0.68, review: "pending_review" },
        { name: "Decorative vase", confidence: 0.47, review: "pending_review" },
        { name: "Wall art",       confidence: 0.53, review: "pending_review" },
        { name: "Bookshelf",      confidence: 0.44, review: "pending_review" },
        { name: "Magazines",      confidence: 0.58, review: "needs_correction" }
      ] },
    { box: "1", slug: "floor-corner", status: "succeeded", captured_at: 180,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a living-room floor corner with a " \
              "rolled area rug, a tall floor lamp, a small wooden coffee table, " \
              "and a ceramic floor vase. Even daylight, eye-level, no text.",
      items: [
        { name: "Area rug",    confidence: 0.58, review: "pending_review" },
        { name: "Floor lamp",  confidence: 0.62, review: "pending_review" },
        { name: "Coffee table", confidence: 0.52, review: "pending_review" },
        { name: "Floor vase",  confidence: 0.51, review: "pending_review" },
        { name: "Wall clock",  confidence: 0.54, review: "pending_review" }
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
        { name: "Hardcover Books", confidence: 0.90, review: "auto_confirmed" },
        { name: "Framed Photos",  confidence: 0.85, review: "auto_confirmed" },
        { name: "Wool Blanket",   confidence: 0.70, review: "confirmed" },
        { name: "Vinyl Records",  confidence: 0.60, review: "pending_review" }
      ] },

    # --- Box 5 (Garage, in_transit): power tools -------------------------------
    { box: "5", slug: "garage-power-tools", status: "succeeded", captured_at: 600,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a workbench with a cordless power " \
              "drill, a coiled orange extension cord, a socket wrench set in a " \
              "case, and safety goggles. Even daylight, eye-level, no text.",
      items: [
        { name: "Cordless Drill", confidence: 0.92, review: "auto_confirmed" },
        { name: "Extension Cord", confidence: 0.80, review: "auto_confirmed" },
        { name: "Socket Set", confidence: 0.70, review: "confirmed" },
        { name: "Safety Goggles", confidence: 0.60, review: "pending_review" }
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
        { name: "Phone Charger", confidence: 0.90, review: "confirmed" },
        { name: "Paperback", confidence: 0.90, review: "confirmed" }
      ] },

    # --- Box 7 (Bedroom, unpacking): in-place checklist demo (#727) — a multi-
    # item photo for the chip toggles and a single-item photo for the one-tap
    # "Unpack photo". Default presence (in_box) so both start toggleable.
    { box: "7", slug: "wardrobe-shelf", status: "succeeded", captured_at: 90,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an open wardrobe shelf with folded " \
              "sweaters, a stack of jeans, and a woven storage basket. Even indoor " \
              "light, no text.",
      items: [
        { name: "Folded Sweaters", confidence: 0.91, review: "auto_confirmed" },
        { name: "Stack of Jeans", confidence: 0.88, review: "confirmed" },
        { name: "Woven Basket", confidence: 0.75, review: "confirmed" }
      ] },
    { box: "7", slug: "bedside-drawer", status: "succeeded", captured_at: 60,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an open bedside drawer holding a " \
              "single hardcover journal. Even indoor light, no text.",
      items: [
        { name: "Hardcover Journal", confidence: 0.93, review: "auto_confirmed" }
      ] },

    # --- Box 9 (Kitchen, packing): removal demo — one photo, two in-box items --
    { box: "9", slug: "skillet-and-bowls", status: "succeeded", captured_at: 120,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a kitchen counter with a black " \
              "cast-iron skillet and a nested set of stainless mixing bowls. " \
              "Even daylight, eye-level, no text.",
      items: [
        { name: "Cast Iron Skillet", confidence: 0.90, review: "confirmed" },
        { name: "Mixing Bowls",     confidence: 0.90, review: "confirmed" }
      ] },

    # --- Box 11 (Office, packing): desk gear. captured_at 560 (not the shared
    # 500) so this is unambiguously the OLDEST pending photo — the queue's FIFO
    # entry point — and the cross-box walk order is deterministic (#656). -------
    { box: "11", slug: "office-desk", status: "succeeded", captured_at: 560, pending_floor: 2,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an office desk with a closed " \
              "laptop, an external monitor, a mechanical keyboard, a desk lamp, " \
              "and a stack of notebooks. Even daylight, eye-level, no text.",
      items: [
        { name: "Laptop",           confidence: 0.95, review: "auto_confirmed" },
        { name: "External Monitor", confidence: 0.88, review: "auto_confirmed" },
        { name: "Mechanical Keyboard", confidence: 0.70, review: "confirmed" },
        { name: "Desk Lamp",        confidence: 0.60, review: "pending_review" },
        { name: "Notebook Stack",   confidence: 0.50, review: "pending_review" }
      ] },

    # --- Box 12 (Bathroom, sealed): toiletries ---------------------------------
    { box: "12", slug: "bathroom-counter", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a bathroom counter with folded " \
              "bath towels, a zipped toiletry bag, an electric toothbrush on its " \
              "charger, and a pump bottle of hand soap. Even light, no text.",
      items: [
        { name: "Bath Towels",       confidence: 0.85, review: "auto_confirmed" },
        { name: "Toiletry Bag",      confidence: 0.70, review: "confirmed" },
        { name: "Electric Toothbrush", confidence: 0.60, review: "pending_review" },
        { name: "Hand Soap", confidence: 0.50, review: "pending_review" }
      ] },

    # --- Box 13 (Dining Room, in_transit): fragile dinnerware ------------------
    { box: "13", slug: "dining-ware", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of a dining table with a stack of " \
              "white dinner plates, a row of stemmed wine glasses, a large " \
              "serving bowl, and a folded linen tablecloth. Even daylight, no text.",
      items: [
        { name: "Dinner Plates", confidence: 0.90, review: "auto_confirmed" },
        { name: "Wine Glasses",  confidence: 0.85, review: "auto_confirmed" },
        { name: "Serving Bowl",  confidence: 0.70, review: "confirmed" },
        { name: "Linen Tablecloth", confidence: 0.60, review: "pending_review" }
      ] },

    # --- Box 14 (Garage, packing): camping gear --------------------------------
    { box: "14", slug: "camping-gear", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of camping gear on a garage floor: a " \
              "packed dome tent in its bag, a rolled sleeping bag, a bicycle " \
              "helmet, and a hand air pump. Even daylight, no text.",
      items: [
        { name: "Camping Tent",  confidence: 0.80, review: "confirmed" },
        { name: "Sleeping Bag",  confidence: 0.70, review: "confirmed" },
        { name: "Bicycle Helmet", confidence: 0.60, review: "pending_review" },
        { name: "Hand Pump", confidence: 0.50, review: "pending_review" }
      ] },

    # --- Box 15 (Living Room, sealed): entertainment ---------------------------
    { box: "15", slug: "entertainment-unit", status: "succeeded", captured_at: 500,
      provider: "fake", provider_model: "fake-1",
      prompt: "A realistic smartphone photo of an entertainment unit with a game " \
              "console, a stack of boxed board games, a streaming remote, and a " \
              "row of DVD cases. Even daylight, eye-level, no text.",
      items: [
        { name: "Game Console",    confidence: 0.90, review: "auto_confirmed" },
        { name: "Board Games",     confidence: 0.70, review: "confirmed" },
        { name: "DVD Collection",  confidence: 0.60, review: "pending_review" },
        { name: "Streaming Remote", confidence: 0.50, review: "pending_review" }
      ] }
  ].freeze

  # Manual items with NO photo (created_via: "manual"). Keyed on name within a box
  # so re-running never duplicates. Spans the review axis (confirmed /
  # needs_correction) and the presence axis (in_box / removed). The box-5 "Hair
  # dryer" backs the semantic-search demo ("blow dryer" ~ "Hair dryer").
  # Some manual items carry a `family` (#702) so the insurance declaration
  # seeds real theme groups; family-less ones showcase the Miscellaneous bucket.
  MANUAL_ITEMS = [
    { box: "2", name: "Espresso Machine", family: "kitchenware",
      review: "confirmed", presence: "in_box" },
    { box: "2", name: "Dinner Plates", family: "kitchenware",
      review: "confirmed", presence: "in_box" },
    { box: "4", name: "Paperback Novels",
      review: "needs_correction", presence: "in_box" },
    { box: "4", name: "Winter Coat",
      review: "confirmed", presence: "removed" },
    { box: "5", name: "Hair dryer",
      review: "confirmed", presence: "in_box" },
    { box: "7", name: "Bedside Lamp", family: "lamps & lighting",
      review: "confirmed", presence: "in_box" },
    { box: "7", name: "Folded Bedsheets", family: "bedding & linens",
      review: "confirmed", presence: "in_box" },
    { box: "7", name: "Alarm Clock",
      review: "confirmed", presence: "in_box" },
    { box: "7", name: "Throw Pillows",
      review: "confirmed", presence: "removed" },
    { box: "7", name: "Reading Glasses",
      review: "confirmed", presence: "removed" },
    # The gallery Groups showcase (#633): a battery family deliberately
    # scattered across three boxes — the epic's headline scenario ("packed
    # in a rush, found anyway"). Word-share similarity clusters them under
    # any provider, so the demo shows Groups with no AI key configured.
    { box: "2", name: "AA batteries", family: "batteries & power",
      review: "confirmed", presence: "in_box" },
    { box: "5", name: "AAA batteries", family: "batteries & power",
      review: "confirmed", presence: "in_box" },
    { box: "7", name: "Battery charger", family: "batteries & power",
      review: "confirmed", presence: "in_box" }
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
  # way: { name:, confidence:, review:, family: } — family is the hidden facet
  # (#626), nil for recordings made before it existed and for authored items
  # that don't declare one. The photo's `pending_floor` is applied last.
  def self.detections_for(photo, threshold:)
    recorded = recorded_recognition(photo[:slug])
    detections =
      if recorded
        normalize_recorded(recorded["objects"], threshold: threshold)
      else
        Array(photo[:items]).map { |item| authored_detection(item) }
      end
    apply_pending_floor(detections, photo[:pending_floor])
  end

  UNREVIEWED_STATES = %w[pending_review needs_correction].freeze

  # Recorded confidences float with whatever the vision model returned, so a
  # re-recording can auto-confirm every detection and silently empty the
  # review-queue demo (#656) — exactly what happened when the committed
  # recordings came back ≥ the 0.8 threshold almost everywhere. `pending_floor:
  # N` pins the demo invariant: at least N of the photo's detections seed
  # unreviewed, demoting the LOWEST-confidence auto-confirmed ones as needed
  # (mirroring how borderline detections behave). A no-op when enough are
  # already unreviewed — the floor never promotes a confirmed state upward.
  def self.apply_pending_floor(detections, floor)
    short = floor.to_i - detections.count { |d| UNREVIEWED_STATES.include?(d[:review]) }
    return detections if short <= 0

    detections.select { |d| d[:review] == "auto_confirmed" }
              .sort_by { |d| d[:confidence].to_f }
              .first(short)
              .each { |d| d[:review] = "pending_review" }
    detections
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
      review: confidence && confidence >= threshold ? "auto_confirmed" : "pending_review",
      family: object["family"].to_s.strip.presence
    }
  end

  def self.authored_detection(item)
    { name: item[:name], confidence: item[:confidence], review: item[:review], family: item[:family] }
  end

  # Active Storage attachable for a photo slug: the committed db/seed_images/<slug>.jpg
  # when present, else the placeholder icon (so seeding/provisioning works offline / on
  # a fresh DB / in CI with no generated photos). Shared by DemoData::SampleBuilder and
  # db/seeds.rb so the two never drift.
  def self.image_attachable(slug)
    path = Rails.root.join("db/seed_images/#{slug}.jpg")
    if path.exist?
      { io: path.open, filename: "#{slug}.jpg", content_type: "image/jpeg" }
    else
      { io: Rails.public_path.join("icon.png").open, filename: "#{slug}.png", content_type: "image/png" }
    end
  end
end

# frozen_string_literal: true

# Showcase / demo seed data — idempotent, safe to re-run.
#
# GOAL: after `bin/rails db:seed` a developer can sign in and immediately play
# with every surface shipped so far (Moves, Boxes Home, …), with records in a
# spread of states (sealed/packing, with/without dimensions, multiple rooms).
#
# Each phase MUST extend this file with comprehensive, idempotent seed data for
# the surfaces it adds (see AGENTS.md §8). Use find_or_create_by so re-running
# never duplicates.
#
# NEVER seeds production: demo accounts + a demo tenant must not reach the live
# registry. `db:prepare` auto-runs seeds on a fresh DB, which is how demo data
# leaked before — this guard is the backstop.
if Rails.env.production?
  Rails.logger.info("[seeds] skipped in production")
  return
end

# Apartment enhances `db:seed` to run once per tenant. This demo provisions its
# own tenant, so run it only from the base (public) schema — otherwise the demo
# (and stray records) would be repeated into every existing tenant schema.
return unless Apartment::Tenant.current == "public"

require "securerandom"

# --- Demo accounts + organization (tenant) ----------------------------------
# Sign in (passwordless) with these emails on the org subdomain
# `<slug>.<tenant_zone>` (dev: acme.workeverywhere.docker):
#   demo@example.com    — admin   (full vocabulary management — D7)
#   member@example.com  — member  (read-only vocabularies: no edit affordance)
DEMO = {
  owner_email: "demo@example.com",
  owner_name: "Demo Mover",
  member_email: "member@example.com",
  member_name: "Demo Member",
  org_name: "Acme Relocation",
  org_slug: "acme"
}.freeze

owner = User.find_or_create_by!(email: DEMO[:owner_email]) do |u|
  u.name = DEMO[:owner_name]
  u.status = 2 # verified — required to sign in via the passwordless email link
end

member = User.find_or_create_by!(email: DEMO[:member_email]) do |u|
  u.name = DEMO[:member_name]
  u.status = 2 # verified
end

organization = Organization.find_by(slug: DEMO[:org_slug])
unless organization
  result = Organizations::Create.new.call(
    name: DEMO[:org_name], slug: DEMO[:org_slug], owner: owner
  )
  raise "[seeds] could not create org: #{result.failure}" if result.failure?

  organization = result.value!
end

# --- Tenant-scoped demo: a Move with rooms and boxes in varied states --------
Apartment::Tenant.switch(organization.slug) do # rubocop:disable Metrics/BlockLength
  move = Move.find_or_create_by!(name: "Seattle Relocation") do |m|
    m.status = "started"
    m.unit_system = "metric"
    m.created_by = owner
  end
  move.move_memberships.find_or_create_by!(user: owner) { |mm| mm.role = "admin" }
  move.move_memberships.find_or_create_by!(user: member) { |mm| mm.role = "member" }

  rooms = ["Kitchen", "Living Room", "Bedroom", "Garage"].index_with do |name|
    move.rooms.find_or_create_by!(name: name)
  end

  # number => attributes. Covers every lifecycle state (packing/sealed/
  # in_transit/unpacking/unpacked), boxes with full / partial / no dimensions,
  # and a roomless box (to demo the seal-requires-room guard).
  boxes = {
    "1" => { room: "Kitchen",     status: "sealed",     dims: [40, 30, 25, 8] },
    "2" => { room: "Kitchen",     status: "packing",    dims: [] },
    "3" => { room: "Living Room", status: "sealed",     dims: [60, 40, 40, 15] },
    "4" => { room: "Bedroom",     status: "packing",    dims: [50, 40, nil, 6] },
    "5" => { room: "Garage",      status: "in_transit", dims: [80, 60, 50, 22] },
    "6" => { room: nil,           status: "packing",    dims: [] },
    "7" => { room: "Bedroom",     status: "unpacking",  dims: [55, 45, 35, 12] },
    "8" => { room: "Living Room", status: "unpacked",   dims: [60, 40, 40, 14] }
  }

  boxes.each do |number, attrs|
    length, width, height, weight = attrs[:dims]
    move.boxes.find_or_create_by!(number: number) do |b|
      b.qr_token = SecureRandom.urlsafe_base64(16)
      b.room = attrs[:room] && rooms[attrs[:room]]
      b.status = attrs[:status]
      b.length_cm = length
      b.width_cm = width
      b.height_cm = height
      b.weight_kg = weight
    end
  end

  # A captured photo + a completed recognition run on box 1, with the auto-confirm
  # vs pending-review item split (Coffee maker/Books auto, Mugs pending). Records
  # are seeded directly (not via the live pipeline) so db:seed is deterministic.
  demo_box = move.boxes.find_by(number: "1")
  if demo_box&.media&.none?
    media = demo_box.media.new(move: move, media_type: "image", captured_via: "web", captured_at: Time.current)
    media.image.attach(
      io: Rails.public_path.join("icon.png").open, filename: "capture.png", content_type: "image/png"
    )
    media.save!
    run = demo_box.recognition_runs.create!(
      move: move, media: media, provider: "fake", provider_model: "fake-1", status: "succeeded",
      started_at: 1.minute.ago, completed_at: Time.current,
      metadata: { "item_count" => 3, "provider" => "fake" }
    )
    [["Coffee maker", 0.97, true], ["Stack of books", 0.88, true], ["Set of mugs", 0.62, false]].each do |name, conf, auto|
      suggestion = run.recognition_suggestions.create!(
        move: move, box: demo_box, media: media, proposed_name: name, proposed_quantity: 1,
        confidence_score: conf, state: auto ? "auto_accepted" : "pending"
      )
      item = demo_box.items.create!(
        move: move, source_media: media, source_recognition_suggestion_id: suggestion.id, name: name,
        quantity: 1, confidence_score: conf, created_via: "recognition",
        review_state: auto ? "auto_confirmed" : "pending_review"
      )
      suggestion.update!(item: item)
    end
  end

  # --- D5/D7: managed vocabularies (categories, tags, rooms) ------------------
  # Selection-only elsewhere; managed on the D7 surfaces. Each vocabulary keeps
  # one *unused* value (Tools / Seasonal / Attic) so the non-in-use remove path
  # is showcase-ready, plus in-use values to demo the remove-with-confirm path.
  categories = %w[Kitchenware Books Electronics Clothing Tools].index_with do |name|
    move.categories.find_or_create_by!(name: name)
  end
  # name => applies_to (item / box / both) — covers every facet the tag rows show.
  {
    "Heavy" => "both", "Everyday Use" => "item", "Liquid" => "item",
    "Important" => "both", "Fragile" => "box", "Seasonal" => "item"
  }.each do |name, applies_to|
    move.tags.find_or_create_by!(name: name) { |t| t.applies_to = applies_to }
  end
  tags = move.tags.index_by(&:name)
  # Rooms already seeded above; add one unused room for the remove demo.
  move.rooms.find_or_create_by!(name: "Attic")

  # Manual items spanning the review axis (confirmed / needs_correction) and the
  # presence axis (in_box / removed), some categorised and tagged. Keyed on name
  # within a box so re-running never duplicates.
  manual_items = [
    { box: "2", name: "Espresso Machine", qty: 1, fragile: true,
      category: "Electronics", tags: ["Heavy"], review: "confirmed", presence: "in_box" },
    { box: "2", name: "Dinner Plates", qty: 8, fragile: true,
      category: "Kitchenware", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    { box: "4", name: "Paperback Novels", qty: 12, fragile: false,
      category: "Books", tags: ["Heavy"], review: "needs_correction", presence: "in_box" },
    { box: "4", name: "Winter Coat", qty: 1, fragile: false,
      category: "Clothing", tags: [], review: "confirmed", presence: "removed" }
  ]
  manual_items.each do |attrs|
    box = move.boxes.find_by(number: attrs[:box])
    next unless box

    item = box.items.find_or_initialize_by(name: attrs[:name])
    next unless item.new_record?

    item.assign_attributes(
      move: move, quantity: attrs[:qty], fragile: attrs[:fragile],
      category: categories[attrs[:category]], created_via: "manual",
      review_state: attrs[:review], presence_state: attrs[:presence],
      tags: attrs[:tags].map { |name| tags[name] }
    )
    item.save!
  end

  # --- D6: a review-ready box — pending suggestions across confidence bands and
  # a conflict (confirmed item + a late detection of the same name) so the review
  # queue (C1) and item-by-item (C2) are showcase-ready. Idempotent by name.
  review_box = move.boxes.find_by(number: "1")
  run = review_box&.recognition_runs&.first
  review_media = review_box&.media&.first
  if run && review_media
    [
      ["Table lamp", 0.55],
      ["Picture frame", 0.41],
      ["Throw blanket", 0.68],
      ["Cast-iron skillet", 0.91],
      ["Decorative vase", 0.47],
      ["Wall Art", 0.53],
      ["Floor Lamp", 0.62],
      ["Area Rug", 0.58],
      ["Decorative Pillow", 0.49],
      ["Bookshelf", 0.44],
      ["Coffee Table", 0.52],
      ["Curtains", 0.39],
      ["Decorative Bowl", 0.46],
      ["Table Runner", 0.43],
      ["Wall Mirror", 0.57],
      ["Decorative Tray", 0.48],
      ["Floor Vase", 0.51],
      ["Throw Pillow", 0.45],
      ["Decorative Lantern", 0.42],
      ["Wall Clock", 0.54]
    ].each do |name, conf|
      next if review_box.recognition_suggestions.exists?(proposed_name: name)

      suggestion = run.recognition_suggestions.create!(
        move: move, box: review_box, media: review_media, proposed_name: name,
        proposed_quantity: 1, confidence_score: conf, state: "pending"
      )
      item = review_box.items.create!(
        move: move, source_media: review_media, source_recognition_suggestion_id: suggestion.id,
        name: name, quantity: 1, confidence_score: conf, created_via: "recognition",
        review_state: "pending_review"
      )
      suggestion.update!(item: item)
    end

    unless review_box.recognition_suggestions.exists?(state: "conflict")
      confirmed = review_box.items.find_or_create_by!(name: "Cast-iron skillet") do |record|
        record.move = move
        record.quantity = 1
        record.created_via = "manual"
        record.review_state = "confirmed"
      end
      run.recognition_suggestions.create!(
        move: move, box: review_box, media: review_media, item: confirmed,
        proposed_name: "Cast-iron skillet", proposed_quantity: 1,
        confidence_score: 0.91, state: "conflict"
      )
    end
  end

  Rails.logger.info(
    "[seeds] #{organization.slug}: #{move.boxes.count} boxes, #{move.rooms.count} rooms, " \
    "#{move.categories.count} categories, #{move.tags.count} tags, " \
    "#{move.items.count} items, #{move.media.count} media, " \
    "#{move.recognition_suggestions.unresolved.count} to review"
  )
end

# --- Misc demo content (Posts surface) --------------------------------------
author = User.find_or_create_by!(email: "john.doe@example.com") { |u| u.name = "John Doe" }
Post.find_or_create_by!(title: "Hello World") do |p|
  p.body = "This is a test post"
  p.user = author
end

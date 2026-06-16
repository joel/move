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
# `<slug>.<tenant_zone>` (dev: acme.workeverywhere.docker). The first three are
# members of the demo Move across all three D11 roles; the fourth is an
# Organization member NOT on the Move, so the F1 "Add member" form has a
# candidate to showcase:
#   demo@example.com     — admin       (manage members, vocabularies, everything)
#   member@example.com   — contributor (add/edit boxes & items; no member mgmt)
#   viewer@example.com   — viewer      (read-only; no edit/manage affordances)
#   invitee@example.com  — org member, addable to the Move via F1
#
# D13 — the demo Move's "Main Assistant" MCP token is the fixed dev value below,
# so you can call the assistant endpoint immediately:
#   curl -s https://acme.workeverywhere.docker/mcp \
#     -H "Authorization: Bearer mcp_demo_seattle_relocation_dev_token" \
#     -H "Content-Type: application/json" \
#     -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_boxes","arguments":{}}}'
DEMO_MCP_TOKEN = "mcp_demo_seattle_relocation_dev_token"
DEMO = {
  owner_email: "demo@example.com",
  owner_name: "Demo Mover",
  member_email: "member@example.com",
  member_name: "Demo Contributor",
  viewer_email: "viewer@example.com",
  viewer_name: "Demo Viewer",
  invitee_email: "invitee@example.com",
  invitee_name: "Demo Invitee",
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

viewer = User.find_or_create_by!(email: DEMO[:viewer_email]) do |u|
  u.name = DEMO[:viewer_name]
  u.status = 2 # verified
end

invitee = User.find_or_create_by!(email: DEMO[:invitee_email]) do |u|
  u.name = DEMO[:invitee_name]
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

# Organization memberships (public schema) for the secondary demo users — a Move
# can only be shared with Organization members, so these back the F1 candidate
# list and the org-bounded invite rule.
[member, viewer, invitee].each do |user|
  organization.organization_memberships.find_or_create_by!(user: user) { |om| om.role = "member" }
end

# --- Tenant-scoped demo: a Move with rooms and boxes in varied states --------
Apartment::Tenant.switch(organization.slug) do # rubocop:disable Metrics/BlockLength
  move = Move.find_or_create_by!(name: "Seattle Relocation") do |m|
    m.status = "started"
    m.unit_system = "metric"
    m.created_by = owner
    # #185 — recognition is per-Move BYO. The demo uses the network-free `fake`
    # provider (no key) so it works offline and shows the Settings "Recognition &
    # AI" panel in its ready state; an admin can switch to a real provider + key.
    m.recognition_provider = "fake"
  end
  # #187 — showcase a per-provider model override. The demo keeps `fake` active
  # (offline), but OpenAI is pinned to a custom model: switching the provider pill
  # in the Settings "Recognition & AI" panel reveals "gpt-5" pre-filled in the
  # editable Model field.
  move.update!(openai_model: "gpt-5") unless move.openai_model == "gpt-5"
  # F1 — all three D11 roles represented on the demo Move. `invitee` is
  # deliberately left off so the "Add member" form has a candidate to show.
  move.move_memberships.find_or_create_by!(user: owner) { |mm| mm.role = "admin" }
  move.move_memberships.find_or_create_by!(user: member) { |mm| mm.role = "contributor" }
  move.move_memberships.find_or_create_by!(user: viewer) { |mm| mm.role = "viewer" }

  # Seed the curated default vocabularies (categories, tags, rooms) that every
  # new Move now gets through Moves::Create. The shared module keeps the seed and
  # the app in lockstep; the demo Move is built directly here (not via the action)
  # so it must call apply itself.
  Moves::DefaultVocabularies.apply(move)
  rooms = move.rooms.index_by(&:name)

  # number => attributes. Covers every lifecycle state (packing/sealed/
  # in_transit/unpacking/unpacked), boxes with full / partial / no dimensions,
  # and a roomless box (to demo the seal-requires-room guard). Sizes repeat on
  # purpose so the Add Box form's "Reuse dimensions" chips have something to
  # offer: 40×30×25 appears 3× (a stack of identical boxes) and 60×40×40 twice.
  # `desc` exercises the contents-description surface: sealed boxes carry one
  # (shown on the detail card); packing boxes 2 and 9 deliberately have none so
  # the ✨ AI-suggest field and the seal-time "describe before sealing" modal are
  # demoable (box 2 also has items, so a real suggestion can be generated).
  boxes = {
    "1" => { room: "Kitchen",     status: "sealed",     dims: [40, 30, 25, 8],
             desc: "Cookware, small appliances, heavy utensils. Keep upright." },
    "2" => { room: "Kitchen",     status: "packing",    dims: [] },
    "3" => { room: "Living Room", status: "sealed",     dims: [60, 40, 40, 15],
             desc: "Books, framed photos, throw blankets." },
    "4" => { room: "Bedroom",     status: "packing",    dims: [50, 40, nil, 6] },
    "5" => { room: "Garage",      status: "in_transit", dims: [80, 60, 50, 22],
             desc: "Power tools, extension cords, hardware." },
    "6" => { room: nil,           status: "packing",    dims: [] },
    "7" => { room: "Bedroom",     status: "unpacking",  dims: [55, 45, 35, 12] },
    "8" => { room: "Living Room", status: "unpacked",   dims: [60, 40, 40, 14] },
    "9" => { room: "Kitchen",     status: "packing",    dims: [40, 30, 25, 7] },
    "10" => { room: "Kitchen", status: "sealed", dims: [40, 30, 25, 9],
              desc: "Clothes, Electronics, Books" }
  }

  boxes.each do |number, attrs|
    length, width, height, weight = attrs[:dims]
    box = move.boxes.find_or_create_by!(number: number) do |b|
      b.qr_token = SecureRandom.urlsafe_base64(16)
      b.room = attrs[:room] && rooms[attrs[:room]]
      b.status = attrs[:status]
      b.description = attrs[:desc]
      b.length_cm = length
      b.width_cm = width
      b.height_cm = height
      b.weight_kg = weight
    end
    # Backfill the showcase description onto a box seeded before this feature
    # existed, so an already-seeded demo tenant shows it after a plain re-seed
    # (the create block runs only on first insert). Only fills a blank, so a
    # developer's own edits and the box's lifecycle state are left untouched.
    box.update!(description: attrs[:desc]) if attrs[:desc].present? && box.description.blank?
  end

  # Box 1 is the review showcase: several photos, each with a handful of detections
  # spanning the confidence bands and review states, so the per-photo review walk
  # (PHOTO X OF Y → "Next Photo" → "Finish review") is demoable end to end — edit a
  # name inline, remove a wrong detection, add a missed item, page to the next
  # photo. Records are seeded directly (not via the live pipeline) so db:seed stays
  # deterministic. (Conflict detections aren't surfaced by the per-photo UI; their
  # seeding returns once #145 settles conflict handling in the new model.)
  #
  # [name, confidence 0-1, review_state] per photo, ordered as the walk visits them.
  review_photos = {
    "Kitchen counter" => [
      ["Coffee maker", 0.97, "auto_confirmed"],
      ["Stack of books", 0.88, "auto_confirmed"],
      ["Set of mugs", 0.62, "pending_review"],
      ["Table lamp", 0.55, "pending_review"],
      ["Picture frame", 0.41, "pending_review"]
    ],
    "Open shelving" => [
      ["Throw blanket", 0.68, "pending_review"],
      ["Decorative vase", 0.47, "pending_review"],
      ["Wall art", 0.53, "pending_review"],
      ["Bookshelf", 0.44, "pending_review"],
      ["Magazines", 0.58, "needs_correction"]
    ],
    "Floor corner" => [
      ["Area rug", 0.58, "pending_review"],
      ["Floor lamp", 0.62, "pending_review"],
      ["Coffee table", 0.52, "pending_review"],
      ["Floor vase", 0.51, "pending_review"],
      ["Wall clock", 0.54, "pending_review"]
    ]
  }

  demo_box = move.boxes.find_by(number: "1")
  if demo_box&.media&.none?
    review_photos.each_with_index do |(label, detections), idx|
      media = demo_box.media.new(
        move: move, media_type: "image", captured_via: "web",
        # Stagger capture times so the walk orders the photos as listed above.
        captured_at: (review_photos.size - idx).minutes.ago
      )
      # Attach before save — Media validates image presence.
      media.image.attach(
        io: Rails.public_path.join("icon.png").open,
        filename: "#{label.parameterize}.png", content_type: "image/png"
      )
      media.save!
      run = demo_box.recognition_runs.create!(
        move: move, media: media, provider: "fake", provider_model: "fake-1", status: "succeeded",
        started_at: 1.minute.ago, completed_at: Time.current,
        metadata: { "item_count" => detections.size, "provider" => "fake" }
      )
      detections.each do |name, conf, review_state|
        suggestion = run.recognition_suggestions.create!(
          move: move, box: demo_box, media: media, proposed_name: name, proposed_quantity: 1,
          confidence_score: conf, state: review_state == "auto_confirmed" ? "auto_accepted" : "pending"
        )
        item = demo_box.items.create!(
          move: move, source_media: media, source_recognition_suggestion_id: suggestion.id,
          name: name, quantity: 1, confidence_score: conf, created_via: "recognition",
          review_state: review_state
        )
        suggestion.update!(item: item)
      end
    end
  end

  # Recovery demo: two orphaned photos in the demo box — one whose recognition
  # FAILED (quota) and one that SUCCEEDED with zero detections. Both have no item,
  # so the gallery shows tappable recovery tiles and the recovery screen is
  # showcase-ready (Retry + Add item manually). Idempotent: the absence of any
  # failed run gates the whole block.
  if demo_box && demo_box.recognition_runs.where(status: "failed").none?
    attach_demo_image = lambda do |media, label|
      media.image.attach(
        io: Rails.public_path.join("icon.png").open,
        filename: "#{label.parameterize}.png", content_type: "image/png"
      )
      media.save!
    end

    failed_media = demo_box.media.new(
      move: move, media_type: "image", captured_via: "web", captured_at: 30.seconds.ago
    )
    attach_demo_image.call(failed_media, "recovery-failed")
    demo_box.recognition_runs.create!(
      move: move, media: failed_media, provider: "openai", provider_model: "gpt-5-mini",
      status: "failed", started_at: 1.minute.ago, completed_at: Time.current,
      error_code: "ProviderHttp::Error",
      error_message: "RecognitionProviders::Openai request failed (429): " \
                     "You exceeded your current quota, please check your plan and billing details."
    )

    empty_media = demo_box.media.new(
      move: move, media_type: "image", captured_via: "web", captured_at: 20.seconds.ago
    )
    attach_demo_image.call(empty_media, "recovery-empty")
    demo_box.recognition_runs.create!(
      move: move, media: empty_media, provider: "fake", provider_model: "fake-1",
      status: "succeeded", started_at: 1.minute.ago, completed_at: Time.current,
      metadata: { "item_count" => 0, "provider" => "fake" }
    )
  end

  # --- D5/D7: managed vocabularies (categories, tags, rooms) ------------------
  # The curated defaults were seeded above via Moves::DefaultVocabularies and
  # already leave several *unused* values (Tools / Seasonal / Attic / Decor / …)
  # so the non-in-use remove path stays showcase-ready, alongside in-use values
  # for the remove-with-confirm path. Add the demo-only "Everyday Use" tag the
  # manual items below reference (it is not part of the curated default set).
  everyday = move.tags.find_or_initialize_by(name: "Everyday Use")
  everyday.applies_to = "item"
  everyday.save!
  categories = move.categories.index_by(&:name)
  tags = move.tags.index_by(&:name)

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
      category: "Clothing", tags: [], review: "confirmed", presence: "removed" },
    # D8 search demo: a confirmed "Hair dryer" so a semantic/fuzzy query like
    # "blow dryer" recovers it (shared "dryer" + embedding proximity).
    { box: "5", name: "Hair dryer", qty: 1, fragile: false,
      category: "Electronics", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    # D10 unpacking demo: box #7 is `unpacking`, seeded with a mix of remaining
    # (in_box) and already-unpacked (removed) items so the E3 checklist shows both
    # the "Remaining Items" tap-targets and the dimmed "Unpacked" section.
    { box: "7", name: "Bedside Lamp", qty: 1, fragile: true,
      category: "Electronics", tags: ["Important"], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Folded Bedsheets", qty: 4, fragile: false,
      category: "Clothing", tags: ["Everyday Use"], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Alarm Clock", qty: 1, fragile: false,
      category: "Electronics", tags: [], review: "confirmed", presence: "in_box" },
    { box: "7", name: "Throw Pillows", qty: 2, fragile: false,
      category: "Clothing", tags: [], review: "confirmed", presence: "removed" },
    { box: "7", name: "Reading Glasses", qty: 1, fragile: true,
      category: nil, tags: ["Important"], review: "confirmed", presence: "removed" }
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

  # (D6 review items are seeded with their photos in the box-1 walk above.)

  # --- D9: an archived Move with a sealed box so the E2 *archived* scan state is
  # showcase-ready (read-only resolve). Scan demo: open /moves/<this move>/scan and
  # enter the box code "demo-archived-box", or scan box #1 of the active Move's
  # printed label. The exterior label (A7) and manifest (A4) print from any box
  # detail via the Print buttons.
  archived_move = Move.find_or_create_by!(name: "Portland Archive") do |m|
    m.status = "archived"
    m.unit_system = "metric"
    m.created_by = owner
  end
  archived_move.move_memberships.find_or_create_by!(user: owner) { |mm| mm.role = "admin" }
  archived_room = archived_move.rooms.find_or_create_by!(name: "Storage")
  # find_or_initialize + assign-then-save so an archived box seeded before D12
  # (by the D9 seeds, with no dimensions) still gets backfilled on re-seed —
  # a create-only block would skip an existing record and leave F2 empty.
  archived_box = archived_move.boxes.find_or_initialize_by(number: "1")
  archived_box.qr_token ||= "demo-archived-box"
  archived_box.room = archived_room
  archived_box.status = "sealed"
  # Dimensioned so F2's read-only summary shows a real total (no unit toggle).
  archived_box.length_cm = 50
  archived_box.width_cm = 40
  archived_box.height_cm = 30
  archived_box.weight_kg = 10
  archived_box.save!
  ["Winter Gear", "Holiday Decor"].each do |name|
    next if archived_box.items.exists?(name: name)

    archived_box.items.create!(
      move: archived_move, name: name, quantity: 1, created_via: "manual", review_state: "confirmed"
    )
  end

  # D13 — MCP integration tokens (F3 Assistant panel). Two active tokens (one
  # recently used, one never) plus a revoked one, so the panel shows live tokens
  # and the model exercises the revoked state. Only the digest is stored; the
  # raw value of "Main Assistant" is the fixed dev token documented above
  # (DEMO_MCP_TOKEN), so a developer can call POST /mcp with it immediately.
  move.integration_tokens.find_or_create_by!(name: "Main Assistant") do |t|
    t.organization_id = organization.id
    t.created_by = owner
    t.token_digest = MoveIntegrationToken.digest(DEMO_MCP_TOKEN)
    t.last_used_at = 2.hours.ago
  end
  move.integration_tokens.find_or_create_by!(name: "Inventory Bot") do |t|
    t.organization_id = organization.id
    t.created_by = owner
    t.token_digest = MoveIntegrationToken.digest(SecureRandom.urlsafe_base64(32))
  end
  move.integration_tokens.find_or_create_by!(name: "Old Laptop Script") do |t|
    t.organization_id = organization.id
    t.created_by = owner
    t.token_digest = MoveIntegrationToken.digest(SecureRandom.urlsafe_base64(32))
    t.revoked_at = 3.days.ago
  end

  # G1 — Activity feed showcase. Replays a few real domain events (recorded by
  # Activity::RecordSubscriber) so the feed has things to read, plus a Restore and
  # a Revert affordance to play with. Idempotent: only when the feed is empty.
  if move.activities.none?
    renamed = move.items.in_box.first
    Items::Rename.new.call(item: renamed, name: "#{renamed.name} (labelled)", editor: owner) if renamed
    movable = move.items.in_box.where.not(id: renamed&.id).first
    target = move.boxes.find_by(number: "9")
    Items::Move.new.call(item: movable, target_box: target, mover: member) if movable && target
    sealable = move.boxes.find_by(number: "2")
    Boxes::TransitionStatus.new.call(box: sealable, to: "sealed", actor: member) if sealable&.packing?
    # A deleted box with a cascaded item — restore it from the feed.
    trash = move.boxes.find_or_create_by!(number: "99") do |b|
      b.qr_token = SecureRandom.urlsafe_base64(16)
      b.room = rooms["Garage"]
      b.status = "packing"
    end
    if trash.items.none?
      trash.items.create!(move: move, name: "Old cables", quantity: 1,
                          created_via: "manual", review_state: "confirmed", presence_state: "in_box")
    end
    Boxes::Delete.new.call(box: trash, actor: owner)
  end

  # D8: build the hybrid-search projection for every seeded item synchronously
  # (background workers don't run during db:seed). Fake embedder → deterministic,
  # no network. After this, search works immediately in /product-review.
  move.items.includes(:category, :tags, box: :room).find_each do |item|
    Search::RefreshDocument.new.call(item: item)
  end

  Rails.logger.info(
    "[seeds] #{organization.slug}: #{move.boxes.count} boxes, #{move.rooms.count} rooms, " \
    "#{move.categories.count} categories, #{move.tags.count} tags, " \
    "#{move.items.count} items, #{move.media.count} media, " \
    "#{move.items.in_box.where(review_state: %w[pending_review needs_correction]).count} to review, " \
    "#{ItemSearchDocument.count} search docs"
  )
end

# --- Misc demo content (Posts surface) --------------------------------------
author = User.find_or_create_by!(email: "john.doe@example.com") { |u| u.name = "John Doe" }
Post.find_or_create_by!(title: "Hello World") do |p|
  p.body = "This is a test post"
  p.user = author
end

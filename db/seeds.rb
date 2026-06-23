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
require Rails.root.join("db/seed_data/catalog").to_s

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
    # #232 — search embeddings are per-Move BYO too. The demo keeps the
    # network-free `fake` embedder so semantic search (the "blow dryer" ~ "Hair
    # dryer" recovery below) works offline; an admin flips Settings → Semantic
    # search to On (OpenAI) once a key is set, which re-embeds every item.
    m.embedding_provider = "fake"
  end
  # #187 — showcase a per-provider model override. The demo keeps `fake` active
  # (offline), but OpenAI is pinned to a custom model: switching the provider pill
  # in the Settings "Recognition & AI" panel reveals "gpt-5" pre-filled in the
  # editable Model field.
  move.update!(openai_model: "gpt-5") unless move.openai_model == "gpt-5"
  # Phase 45 — showcase the per-Move "Labels per box" preference at a non-default 3
  # (default is 2: lid + side), so Settings → Move Preferences shows the select on
  # "3" and both label prints emit 3 pages per box. Idempotent.
  move.update!(labels_per_box: 3) unless move.labels_per_box == 3
  # #242 — showcase the shared "AI Capability" panel. Placeholder keys (never
  # real) for three vendors so the panel renders "Key set ••••" rows and the
  # Recognition/Semantic Search selectors light up their keyed options; Anthropic
  # is left unset so a "Not set" row + a disabled "needs key" pill also show. The
  # active providers stay `fake` (offline), so no real API call is ever made.
  move.update!(
    openai_api_key: move.openai_api_key.presence || "demo-openai-key-0001",
    gemini_api_key: move.gemini_api_key.presence || "demo-gemini-key-0002",
    voyage_api_key: move.voyage_api_key.presence || "demo-voyage-key-0003"
  )
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

  # Boxes across every lifecycle state (packing/sealed/in_transit/unpacking/
  # unpacked), a full/partial/no dimension spread, a roomless box (the
  # seal-requires-room guard) and repeated sizes (the Add Box "Reuse dimensions"
  # chips) — see SeedData::BOXES. This spread also exercises the Menu's "Bulk box
  # steps" surface (Phase 44). `desc` exercises the contents-description surface;
  # packing boxes 2/6/9 deliberately have none so the ✨ AI-suggest field and the
  # seal-time "describe before sealing" modal are demoable.
  SeedData::BOXES.each do |attrs|
    length, width, height, weight = attrs[:dims]
    box = move.boxes.find_or_create_by!(number: attrs[:number]) do |b|
      b.qr_token = SecureRandom.urlsafe_base64(16)
      b.room = attrs[:room] && rooms[attrs[:room]]
      b.status = attrs[:status]
      b.description = attrs[:desc]
      b.length_cm = length
      b.width_cm = width
      b.height_cm = height
      b.weight_kg = weight
    end
    # Backfill a showcase description onto a box seeded before this feature
    # existed, so a re-seed shows it (the create block runs only on first insert).
    # Only fills a blank, leaving developer edits and lifecycle state untouched.
    box.update!(description: attrs[:desc]) if attrs[:desc].present? && box.description.blank?
  end

  # The demo-only "Everyday Use" tag the items below reference (not part of the
  # curated default set). The indices resolve catalog category/tag names → records.
  everyday = move.tags.find_or_initialize_by(name: "Everyday Use")
  everyday.applies_to = "item"
  everyday.save!
  categories = move.categories.index_by(&:name)
  tags = move.tags.index_by(&:name)

  # Attach the generated 1:1 demo photo for a slug once it's been generated and
  # committed (db/seed_images/<slug>.jpg via `rails seed_images:generate`); else
  # fall back to the placeholder icon so db:seed works offline / on a fresh DB / CI.
  seed_image_attachable = lambda do |slug|
    path = Rails.root.join("db/seed_images/#{slug}.jpg")
    if path.exist?
      { io: path.open, filename: "#{slug}.jpg", content_type: "image/jpeg" }
    else
      { io: Rails.public_path.join("icon.png").open, filename: "#{slug}.png", content_type: "image/png" }
    end
  end

  # Photos → one Media + one generated image each (SeedData::PHOTOS). Covers the
  # per-photo review walk (box 1: PHOTO X OF Y → "Next Photo" → "Finish review"
  # across the confidence/review-state bands — edit a name inline, remove a wrong
  # detection, add a missed item, page on), the recovery tiles (a FAILED run + a
  # SUCCEEDED-with-zero-detections run = orphaned photos showing Retry / Add item
  # manually), and the phase-aware removal demo (#288: box 9 photo sourcing two
  # in-box items; box 7 photo whose items are all already unpacked → "Unpacked"
  # badge). Seeded directly (not via the live pipeline) so db:seed stays
  # deterministic. Idempotent per box: skipped once the box already has any media.
  SeedData::PHOTOS.group_by { |photo| photo[:box] }.each do |box_number, photos|
    box = move.boxes.find_by(number: box_number)
    next unless box&.media&.none?

    photos.each do |photo|
      media = box.media.new(
        move: move, media_type: "image", captured_via: "web",
        # Stagger capture times so the box-1 walk orders the photos as listed.
        captured_at: photo[:captured_at].seconds.ago
      )
      # Attach before save — Media validates image presence.
      media.image.attach(seed_image_attachable.call(photo[:slug]))
      media.save!

      run_attrs = { move: move, media: media, provider: photo[:provider],
                    provider_model: photo[:provider_model],
                    started_at: 1.minute.ago, completed_at: Time.current }
      if photo[:status] == "failed"
        box.recognition_runs.create!(run_attrs.merge(
                                       status: "failed", error_code: photo[:error_code],
                                       error_message: photo[:error_message]
                                     ))
        next
      end

      run = box.recognition_runs.create!(run_attrs.merge(
                                           status: "succeeded",
                                           metadata: { "item_count" => photo[:items].size,
                                                       "provider" => photo[:provider] }
                                         ))
      photo[:items].each do |attrs|
        suggestion = run.recognition_suggestions.create!(
          move: move, box: box, media: media, proposed_name: attrs[:name],
          proposed_quantity: attrs[:qty] || 1, confidence_score: attrs[:confidence],
          state: attrs[:review] == "auto_confirmed" ? "auto_accepted" : "pending"
        )
        item = box.items.create!(
          move: move, source_media: media, source_recognition_suggestion_id: suggestion.id,
          name: attrs[:name], quantity: attrs[:qty] || 1, fragile: attrs[:fragile] || false,
          confidence_score: attrs[:confidence], created_via: "recognition",
          review_state: attrs[:review], presence_state: attrs[:presence] || "in_box",
          category: categories[attrs[:category]], tags: (attrs[:tags] || []).filter_map { |name| tags[name] }
        )
        suggestion.update!(item: item)
      end
    end
  end

  # Manual items with NO photo (SeedData::MANUAL_ITEMS) spanning the review axis
  # (confirmed / needs_correction) and presence axis (in_box / removed), some
  # categorised and tagged. Keyed on name within a box so re-running never
  # duplicates. The curated default vocabularies above already leave several
  # *unused* values (Tools / Seasonal / Attic / …) so the non-in-use remove path
  # stays showcase-ready, alongside these in-use values for remove-with-confirm.
  SeedData::MANUAL_ITEMS.each do |attrs|
    box = move.boxes.find_by(number: attrs[:box])
    next unless box

    item = box.items.find_or_initialize_by(name: attrs[:name])
    next unless item.new_record?

    item.assign_attributes(
      move: move, quantity: attrs[:qty], fragile: attrs[:fragile],
      category: categories[attrs[:category]], created_via: "manual",
      review_state: attrs[:review], presence_state: attrs[:presence],
      tags: attrs[:tags].filter_map { |name| tags[name] }
    )
    item.save!
  end

  # --- Phase 43: a completed bulk label-print run so the E1 progress/download page
  # is showcase-ready without generating live (the form starts a fresh run). The PDF
  # is rendered from boxes 1–3 against this org's subdomain so the QR codes resolve.
  label_range = move.boxes.in_number_range(1, 3).includes(:room)
  if label_range.exists?
    label_run = move.label_print_runs.find_or_create_by!(from_number: 1, to_number: 3) do |r|
      r.total_count = label_range.count
      r.completed_count = r.total_count
      r.status = "completed"
      r.started_at = 1.minute.ago
      r.finished_at = Time.current
    end
    unless label_run.document.attached?
      label_host = "#{Apartment::Tenant.current}.#{Rails.application.config.x.tenant_zone}"
      label_entries = label_range.map do |box|
        { box: box,
          scan_url: Rails.application.routes.url_helpers.move_scan_resolve_url(
            move, box.qr_token, host: label_host, protocol: "https"
          ) }
      end
      label_run.document.attach(
        io: StringIO.new(BoxLabelsPdf.new(entries: label_entries).render),
        filename: "boxes-001-003-labels.pdf", content_type: "application/pdf"
      )
    end
  end

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

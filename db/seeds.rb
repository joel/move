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

# This seed builds the dev showcase Move explicitly, so suppress the signup
# auto-provisioner (#432) — otherwise creating the demo org would also enqueue an
# auto "Sample move", duplicating contents into the demo tenant.
DemoData.auto_provision = false

# --- Demo accounts + organization (tenant) ----------------------------------
# Sign in (passwordless) with these emails on the org subdomain
# `<slug>.<tenant_zone>` (dev: acme.move-easy.docker). The first three are
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
#   curl -s https://acme.move-easy.docker/mcp \
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

# #369 — the terms-agreement gate redirects any account that hasn't accepted the
# current terms version. Pre-accept for every demo account (via the same action
# the app uses, so it stays in sync) so `/product-review` lands straight in the
# app instead of the agreement wall. Runs after the org is provisioned so a
# failed org create never leaves stray acceptances. Idempotent — Terms::Accept is
# a no-op on a second run.
[owner, member, viewer, invitee].each do |user|
  Terms::Accept.new.call(user: user)
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
    # #416 — item-image generation is per-Move BYO too. The demo uses the
    # network-free `fake` generator (a placeholder PNG, no key) so the "✨ generate
    # image" button on a photo-less manual item works offline; an admin switches to
    # OpenAI by adding a key in Settings (the default for a real Move).
    m.image_provider = "fake"
    # In dev this showcase Move doubles as the onboarding sample exemplar (#432), so
    # it carries the Sample badge + "Remove sample" affordance for /product-review.
    m.sample = true
  end
  move.update!(sample: true) unless move.sample?
  # No live "preparing…" placeholder in dev — this Move is built synchronously.
  organization.update!(demo_data_status: "provisioned") unless organization.demo_data_status == "provisioned"
  # #187 — showcase a per-provider model override. The demo keeps `fake` active
  # (offline), but OpenAI is pinned to a custom model: switching the provider pill
  # in the Settings "Recognition & AI" panel reveals "gpt-5" pre-filled in the
  # editable Model field.
  move.update!(openai_model: "gpt-5") unless move.openai_model == "gpt-5"
  # Phase 45 — showcase the per-Move "Labels per box" preference at a non-default 3
  # (default is 2: lid + side), so Settings → Move Preferences shows the select on
  # "3" and both label prints emit 3 pages per box. Idempotent.
  move.update!(labels_per_box: 3) unless move.labels_per_box == 3
  # #416 — keep the demo on the network-free `fake` image generator on re-seed too
  # (the create-block above only runs on first create), so the "✨ generate image"
  # affordance is always showcasable offline.
  move.update!(image_provider: "fake") unless move.image_provider == "fake"
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

  # Seed the curated default vocabulary (rooms) that every
  # new Move now gets through Moves::Create. The shared module keeps the seed and
  # the app in lockstep; the demo Move is built directly here (not via the action)
  # so it must call apply itself.
  Moves::DefaultVocabularies.apply(move)
  rooms = move.rooms.index_by(&:name)

  # Build the Move's belongings from the full committed catalog via the shared
  # builder — boxes across every lifecycle state, photos with replayed recognition
  # + items, and photo-less manual items — the SAME code the signup sample Move
  # provisions through (#432), so the dev showcase and the production sample never
  # drift. `box_numbers: nil` = the whole catalog (the sample passes a subset).
  # Idempotent: boxes keyed on number, a box's photos skipped once it has media,
  # manual items keyed on name.
  DemoData::SampleBuilder.call(move: move)

  # One AI-generated photo (#416) so the Gallery's "Generated" badge state is
  # showcase-ready — the per-Move Gallery shows ALL media (generated included),
  # unlike the box review walk which excludes them. Attach a committed seed image
  # to a photo-less manual item as its generated source_media. Idempotent: skipped
  # once any generated media exists (keyed on captured_via).
  unless move.media.exists?(captured_via: "generated")
    target = move.items.where(source_media_id: nil).order(:created_at).first
    if target&.box
      generated = target.box.media.new(
        move: move, media_type: "image", captured_via: "generated", captured_at: Time.current
      )
      generated.image.attach(SeedData.image_attachable(SeedData::PHOTOS.first[:slug]))
      generated.save!
      target.update!(source_media: generated)
    end
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
      move: archived_move, name: name, created_via: "manual", review_state: "confirmed"
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
      trash.items.create!(move: move, name: "Old cables",
                          created_via: "manual", review_state: "confirmed", presence_state: "in_box")
    end
    Boxes::Delete.new.call(box: trash, actor: owner)
  end

  # D8: build the hybrid-search projection for every seeded item synchronously
  # (background workers don't run during db:seed). Fake embedder → deterministic,
  # no network. After this, search works immediately in /product-review.
  move.items.includes(box: :room).find_each do |item|
    Search::RefreshDocument.new.call(item: item)
  end

  Rails.logger.info(
    "[seeds] #{organization.slug}: #{move.boxes.count} boxes, #{move.rooms.count} rooms, " \
    "#{move.items.count} items, #{move.media.count} media, " \
    "#{move.items.in_box.where(review_state: %w[pending_review needs_correction]).count} to review, " \
    "#{ItemSearchDocument.count} search docs"
  )
end

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

# --- Demo account + organization (tenant) -----------------------------------
# Sign in (passwordless) with this email on the org subdomain
# `<slug>.<tenant_zone>` (dev: acme.workeverywhere.docker).
DEMO = {
  owner_email: "demo@example.com",
  owner_name: "Demo Mover",
  org_name: "Acme Relocation",
  org_slug: "acme"
}.freeze

owner = User.find_or_create_by!(email: DEMO[:owner_email]) do |u|
  u.name = DEMO[:owner_name]
  u.status = 2 # verified — required to sign in via the passwordless email link
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
Apartment::Tenant.switch(organization.slug) do
  move = Move.find_or_create_by!(name: "Seattle Relocation") do |m|
    m.status = "started"
    m.unit_system = "metric"
    m.created_by = owner
  end
  move.move_memberships.find_or_create_by!(user: owner) { |mm| mm.role = "admin" }

  rooms = ["Kitchen", "Living Room", "Bedroom", "Garage"].index_with do |name|
    move.rooms.find_or_create_by!(name: name)
  end

  # number => attributes. Covers: sealed + full dims, packing + missing dims,
  # partial dims (missing height), in_transit, and a roomless box.
  boxes = {
    "1" => { room: "Kitchen",     status: "sealed",     dims: [40, 30, 25, 8] },
    "2" => { room: "Kitchen",     status: "packing",    dims: [] },
    "3" => { room: "Living Room", status: "sealed",     dims: [60, 40, 40, 15] },
    "4" => { room: "Bedroom",     status: "packing",    dims: [50, 40, nil, 6] },
    "5" => { room: "Garage",      status: "in_transit", dims: [80, 60, 50, 22] },
    "6" => { room: nil,           status: "packing",    dims: [] }
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

  Rails.logger.info(
    "[seeds] #{organization.slug}: #{move.boxes.count} boxes, #{move.rooms.count} rooms"
  )
end

# --- Misc demo content (Posts surface) --------------------------------------
author = User.find_or_create_by!(email: "john.doe@example.com") { |u| u.name = "John Doe" }
Post.find_or_create_by!(title: "Hello World") do |p|
  p.body = "This is a test post"
  p.user = author
end

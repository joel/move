# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

# Rodauth account status: 1 = unverified, 2 = verified, 3 = closed. Seed users
# are pre-verified so they can sign in immediately (an unverified account is
# rejected at login with "awaiting verification").
VERIFIED_STATUS = 2

def seed_user(email, name)
  User.find_or_create_by!(email:) { |u| u.name = name }.tap do |user|
    user.update!(name:, status: VERIFIED_STATUS)
  end
end

user = seed_user("john.doe@example.com", "John Doe")
Post.find_or_create_by!(title: "Hello World", body: "This is a test post", user:)

# Phase D1 — sample Organizations on two subdomains for tenancy verification:
#   https://john.workeverywhere.docker  ·  https://acme.workeverywhere.docker
acme_owner = seed_user("joel@acme.org", "Joel Azemar")

{
  "john" => { name: "Doe Household", owner: user },
  "acme" => { name: "Acme Relocation", owner: acme_owner }
}.each do |slug, attrs|
  organization = Organization.find_or_create_by!(slug:) do |org|
    org.name = attrs[:name]
    org.created_by_user = attrs[:owner]
  end
  OrganizationMembership.find_or_create_by!(organization:, user: attrs[:owner]) do |membership|
    membership.account_admin = true
  end
end

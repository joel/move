# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
user = User.find_or_create_by!(name: "John Doe", email: "john.doe@example.com")
Post.find_or_create_by!(title: "Hello World", body: "This is a test post", user:)

# Phase D1 — sample Organizations on two subdomains for tenancy verification:
#   https://john.move.workeverywhere.docker  ·  https://acme.move.workeverywhere.docker
acme_owner = User.find_or_create_by!(email: "joel@acme.org") { |u| u.name = "Joel Azemar" }

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

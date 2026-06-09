FactoryBot.define do
  factory :move_integration_token do
    move
    organization_id { SecureRandom.uuid }
    created_by factory: %i[user]
    sequence(:name) { |n| "Assistant #{n}" }
    # A realistic digest by default; specs that need the raw token mint it
    # explicitly with the model helpers.
    token_digest { MoveIntegrationToken.digest(MoveIntegrationToken.generate_raw_token) }

    trait :revoked do
      revoked_at { Time.current }
    end
  end
end

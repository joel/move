# frozen_string_literal: true

FactoryBot.define do
  factory :move_invitation do
    organization
    move_id { SecureRandom.uuid }
    sequence(:email) { |n| "invitee-#{n}@example.com" }
    role { "contributor" }
    invited_by factory: :user
    token_digest { MoveInvitation.digest(SecureRandom.urlsafe_base64(32)) }
    expires_at { MoveInvitation::TTL.from_now }

    trait :accepted do
      accepted_at { Time.current }
    end

    trait :revoked do
      revoked_at { Time.current }
    end

    trait :expired do
      expires_at { 1.hour.ago }
    end
  end
end

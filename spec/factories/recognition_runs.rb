# frozen_string_literal: true

FactoryBot.define do
  factory :recognition_run do
    move
    box { association :box, move: move }
    media { association :media, move: move, box: box }
    provider { "fake" }
    provider_model { "fake-1" }
    status { "queued" }

    trait :processing do
      status { "processing" }
      started_at { Time.current }
    end

    trait :succeeded do
      status { "succeeded" }
      started_at { 1.minute.ago }
      completed_at { Time.current }
    end

    trait :failed do
      status { "failed" }
      error_code { "provider_error" }
      error_message { "Provider unavailable" }
      completed_at { Time.current }
    end
  end
end

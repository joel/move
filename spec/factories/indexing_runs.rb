# frozen_string_literal: true

FactoryBot.define do
  factory :indexing_run do
    move
    provider { "openai" }
    status { "queued" }
    total_count { 10 }
    completed_count { 0 }
    failed_count { 0 }

    trait :processing do
      status { "processing" }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      completed_count { total_count }
      started_at { 1.minute.ago }
      finished_at { Time.current }
    end

    trait :superseded do
      status { "superseded" }
      finished_at { Time.current }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :media do
    move
    box { association :box, move: move }
    media_type { "image" }
    captured_via { "web" }
    captured_at { Time.current }
    # Default is a fully-ingested media with its master attached (#545). The
    # :pending trait models a just-created capture whose IngestJob hasn't run.
    status { "ready" }
    transient { with_image { true } }

    after(:build) do |media, evaluator|
      next unless evaluator.with_image

      media.image.attach(
        io: Rails.root.join("spec/fixtures/files/sample_image.png").open,
        filename: "sample_image.png",
        content_type: "image/png"
      )
    end

    # A capture awaiting ingest: no image yet, status pending (#545).
    trait :pending do
      status { "pending" }
      with_image { false }
    end
  end
end

# frozen_string_literal: true

FactoryBot.define do
  factory :recognition_suggestion do
    move
    box { association :box, move: move }
    media { association :media, move: move, box: box }
    recognition_run { association :recognition_run, move: move, box: box, media: media }
    proposed_name { "Coffee Maker" }
    confidence_score { 0.95 }
    state { "pending" }

    trait :conflict do
      state { "conflict" }
    end

    # A pending suggestion cross-linked to its materialized pending_review item,
    # mirroring what RecognitionRuns::Process builds — the unit the queue reviews.
    trait :with_item do
      after(:create) do |suggestion|
        item = create(
          :item, move: suggestion.move, box: suggestion.box,
                 name: suggestion.proposed_name,
                 confidence_score: suggestion.confidence_score, created_via: "recognition",
                 review_state: "pending_review", source_media: suggestion.media,
                 source_recognition_suggestion_id: suggestion.id
        )
        suggestion.update!(item: item)
      end
    end
  end
end

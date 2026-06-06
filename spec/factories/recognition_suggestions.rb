# frozen_string_literal: true

FactoryBot.define do
  factory :recognition_suggestion do
    move
    box { association :box, move: move }
    media { association :media, move: move, box: box }
    recognition_run { association :recognition_run, move: move, box: box, media: media }
    proposed_name { "Coffee Maker" }
    proposed_quantity { 1 }
    confidence_score { 0.95 }
    state { "pending" }
  end
end

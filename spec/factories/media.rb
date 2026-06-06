# frozen_string_literal: true

FactoryBot.define do
  factory :media do
    move
    box { association :box, move: move }
    media_type { "image" }
    captured_via { "web" }
    captured_at { Time.current }

    after(:build) do |media|
      media.image.attach(
        io: Rails.root.join("spec/fixtures/files/sample_image.png").open,
        filename: "sample_image.png",
        content_type: "image/png"
      )
    end
  end
end

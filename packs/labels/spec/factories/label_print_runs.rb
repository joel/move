# frozen_string_literal: true

FactoryBot.define do
  factory :label_print_run do
    move
    from_number { 1 }
    to_number { 10 }
    total_count { 10 }
    completed_count { 0 }
    status { "queued" }

    trait :processing do
      status { "processing" }
      completed_count { 3 }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      completed_count { total_count }
      started_at { 1.minute.ago }
      finished_at { Time.current }
      after(:build) do |run|
        run.document.attach(
          io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "labels.pdf", content_type: "application/pdf"
        )
      end
    end

    trait :failed do
      status { "failed" }
      finished_at { Time.current }
    end
  end
end

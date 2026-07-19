# frozen_string_literal: true

FactoryBot.define do
  factory :insurance_dossier_run do
    move
    total_count { 5 }
    item_count { 20 }
    completed_count { 0 }
    status { "queued" }

    trait :processing do
      status { "processing" }
      completed_count { 2 }
      started_at { Time.current }
    end

    trait :completed do
      status { "completed" }
      completed_count { total_count }
      started_at { 1.minute.ago }
      finished_at { Time.current }
      after(:build) do |run|
        run.document.attach(
          io: StringIO.new("%PDF-1.4\n%fake\n"), filename: "insurance-claim-dossier.pdf",
          content_type: "application/pdf"
        )
      end
    end

    trait :failed do
      status { "failed" }
      finished_at { Time.current }
    end
  end
end

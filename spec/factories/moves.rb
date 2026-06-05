FactoryBot.define do
  factory :move do
    name { "Spring Move" }
    status { "planned" }
    unit_system { "metric" }
    created_by factory: %i[user]

    trait :archived do
      status { "archived" }
    end
  end
end

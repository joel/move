FactoryBot.define do
  factory :move_membership do
    move
    user
    role { "member" }

    trait :admin do
      role { "admin" }
    end
  end
end

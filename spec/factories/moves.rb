FactoryBot.define do
  factory :move do
    name { "Spring Move" }
    status { "planned" }
    unit_system { "metric" }
    created_by factory: %i[user]

    trait :archived do
      status { "archived" }
    end

    trait :sample do
      sample { true }
    end

    # Mirror Moves::Create: the creator is the Move's first admin member. This
    # lets move-scoped specs act as the creator (a full-access admin) without
    # wiring a membership by hand, matching how Moves are really created (D11).
    # Idempotent so a spec that also adds the creator explicitly won't collide.
    after(:create) do |move, _evaluator|
      if move.created_by && move.move_memberships.where(user_id: move.created_by_id).none?
        move.move_memberships.create!(user: move.created_by, role: "admin")
      end
    end
  end
end

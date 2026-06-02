# Source: https://github.com/thoughtbot/factory_bot_rails/blob/v6.4.2/lib/generators/factory_bot/model/templates/factories.erb
FactoryBot.define do
  sequence(:email) { |n| "user#{n}@example.com" }

  factory :user do
    name { "MyString" }
    email { generate(:email) }

    trait :admin do
      roles { [:admin] }
    end
  end
  # Here !!!
end

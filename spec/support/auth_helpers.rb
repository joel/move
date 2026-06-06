# frozen_string_literal: true

module AuthHelpers
  def stub_current_user(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
  end

  def stub_current_tenant(slug)
    allow_any_instance_of(ApplicationController).to receive(:current_tenant).and_return(slug)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :controller
  config.include AuthHelpers, type: :request
  config.include AuthHelpers, type: :system
end

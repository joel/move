# frozen_string_literal: true

RSpec.configure do |config|
  config.before(:each, type: :system) do
    # driven_by :rack_test # rack_test by default, for performance
    driven_by (ENV["TEST_BROWSER"] || :selenium_chrome).to_sym, screen_size: [1400, 1400]
  end

  config.before(:each, :js, type: :system) do
    driven_by :selenium_chrome_headless # selenium when we need javascript
  end
end

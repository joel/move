# frozen_string_literal: true

# Headless Chrome with CI-safe flags (--no-sandbox / --disable-dev-shm-usage are
# needed on GitHub-hosted / containerised runners). Used for :js system specs.
Capybara.register_driver(:move_headless_chrome) do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.add_argument("--headless=new")
  options.add_argument("--no-sandbox")
  options.add_argument("--disable-dev-shm-usage")
  options.add_argument("--disable-gpu")
  options.add_argument("--window-size=1400,1400")
  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    # driven_by :rack_test # rack_test by default, for performance
    driven_by (ENV["TEST_BROWSER"] || :selenium_chrome).to_sym, screen_size: [1400, 1400]
  end

  config.before(:each, :js, type: :system) do
    driven_by :move_headless_chrome # selenium when we need javascript
  end
end

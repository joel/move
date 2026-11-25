# frozen_string_literal: true

require "capybara/selenium/driver"
require "capybara/selenium/driver_specializations/chrome_driver"

# Chrome 158 rejects the wildcard origin that Capybara 3.40 (the latest
# release) passes to `Storage.clearDataForOrigin` when it resets the session
# between examples ("invalid argument: * is not a valid URL"), which fails
# every :js system spec in teardown. Keep the reset's effect without the
# wildcard: clear the current page's localStorage before Capybara navigates to
# about:blank, and clear every cookie with Network.clearBrowserCookies when the
# wildcard call is refused. Older Chromes still take the original path. Delete
# this file once Capybara ships its own fix.
module CapybaraChromeWildcardReset
  #: () -> void
  def reset!
    clear_current_local_storage if @browser
    super
  end

  #: (String cmd, ?Hash[Symbol, untyped] params) -> untyped
  def execute_cdp(cmd, params = {})
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError
    raise unless cmd == "Storage.clearDataForOrigin" && params[:origin] == "*"

    super("Network.clearBrowserCookies")
  end

  private

  #: () -> void
  def clear_current_local_storage
    @browser.execute_script("window.localStorage.clear()")
  rescue Selenium::WebDriver::Error::WebDriverError
    # Reason: about:blank / data: pages have no localStorage, and an open alert
    # is handled by Capybara's own reset right after this.
    nil
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(CapybaraChromeWildcardReset)

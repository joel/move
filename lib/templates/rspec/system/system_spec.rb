require 'rails_helper'

RSpec.describe "<%= class_name.pluralize %>", <%= type_metatag(:system) %> do
  before do
    driven_by(:selenium_chrome_headless)
  end

  pending "add some scenarios (or delete) #{__FILE__}"
end

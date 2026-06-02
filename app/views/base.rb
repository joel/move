# frozen_string_literal: true

module Views
  class Base < Components::Base
    include Phlex::Rails::Helpers::ContentFor
  end
end

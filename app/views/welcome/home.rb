# frozen_string_literal: true

module Views
  module Welcome
    class Home < Views::Base
      def view_template
        h1(class: "font-bold text-4xl") { "Welcome#home" }
        p { "Find me in app/views/welcome/home.rb" }
      end
    end
  end
end

# frozen_string_literal: true

module Components
  class Base < Phlex::HTML
    include Phlex::Rails::Helpers::Routes

    if Rails.env.development?
      def before_template
        comment { "Begin #{self.class.name}" }
        super
      end
    end
  end
end

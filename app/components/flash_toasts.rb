# frozen_string_literal: true

module Components
  # Renders Rails flash messages as Move design-system toasts. `notice` maps to
  # the success (sage) variant; everything else to the error (terracotta) variant.
  class FlashToasts < Components::Base
    include Phlex::Rails::Helpers::Flash

    def view_template
      return unless flash.any?

      div(class: "pointer-events-none fixed right-6 top-20 md:top-6 z-50 " \
                 "flex w-[calc(100vw-3rem)] max-w-sm flex-col gap-3") do
        flash.each do |type, message|
          variant = type.to_s == "notice" ? :success : :error
          render Components::Ui::Toast.new(variant: variant, message: message)
        end
      end
    end
  end
end

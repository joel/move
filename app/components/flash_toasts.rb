# frozen_string_literal: true

module Components
  # Renders Rails flash messages as Move design-system toasts. `notice` maps to
  # the success (sage) variant; everything else to the error (terracotta) variant.
  class FlashToasts < Components::Base
    include Phlex::Rails::Helpers::Flash

    # Stable id so a Turbo Stream response (e.g. the in-place AI settings writes,
    # #260) can replace the toast region to surface a flash.now message without a
    # full reload. The container always renders (even empty) so the target exists.
    ID = "flash-toasts"

    # Flash keys carrying toast *metadata* rather than their own message: an
    # optional call-to-action link on the success toast (e.g. "View" a created
    # record) and the just-created id the page highlights. Skipped here so they
    # never render as stray error toasts.
    META_KEYS = %w[action_href action_label highlight_box_id].freeze

    def view_template
      div(id: ID, class: "pointer-events-none fixed right-6 top-20 md:top-6 z-50 " \
                         "flex w-[calc(100vw-3rem)] max-w-sm flex-col gap-3") do
        flash.each do |type, message|
          next if META_KEYS.include?(type.to_s)

          variant = type.to_s == "notice" ? :success : :error
          render Components::Ui::Toast.new(
            variant: variant, message: message,
            action_href: (flash[:action_href] if variant == :success),
            action_label: (flash[:action_label] if variant == :success)
          )
        end
      end
    end
  end
end

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

    # Allow-list of flash keys that carry a user-facing toast *message*. Anything
    # else in the flash — the action-link metadata below, a page-specific
    # highlight id, any future out-of-band key — is not a toast and is skipped.
    # (An allow-list, not a deny-list, so a new metadata key can never render as a
    # stray toast by omission.)
    TOAST_VARIANTS = { "notice" => :success, "alert" => :error, "error" => :error }.freeze

    #: () -> void
    def view_template
      div(id: ID, class: "pointer-events-none fixed right-6 top-20 md:top-6 z-50 " \
                         "flex w-[calc(100vw-3rem)] max-w-sm flex-col gap-3") do
        flash.each do |type, message|
          variant = TOAST_VARIANTS[type.to_s]
          next unless variant

          render Components::Ui::Toast.new(
            variant: variant, message: message,
            # The "View" link rides along only with a success toast (the create flow).
            action_href: (flash[:action_href] if variant == :success),
            action_label: (flash[:action_label] if variant == :success)
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

module Components
  module Icons
    # Vertical "more actions" kebab (⋮) — the Manage-box sheet trigger (B1).
    class EllipsisVertical < Components::Icons::Base
      #: () -> void
      def view_template
        svg(
          class: @css, **@attrs, viewBox: "0 0 24 24", fill: "currentColor",
          aria_hidden: "true"
        ) do |s|
          s.circle(cx: "12", cy: "5", r: "1.6")
          s.circle(cx: "12", cy: "12", r: "1.6")
          s.circle(cx: "12", cy: "19", r: "1.6")
        end
      end
    end
  end
end

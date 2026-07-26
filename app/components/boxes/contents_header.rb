# frozen_string_literal: true

module Components
  module Boxes
    # The contents grid's title + count row (extracted from ContentsGrid, #727).
    # Carries a stable DOM id so unpacking toggles can tick the count in place
    # over Turbo Streams. With `unpacked:` (unpacking boxes) it renders the
    # progress variant ("2 of 8 unpacked") instead of the plain item count.
    class ContentsHeader < Components::Base
      ID = "box-contents-header"

      #: (total: Integer, ?unpacked: Integer?) -> void
      def initialize(total:, unpacked: nil)
        @total = total
        @unpacked = unpacked
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex items-center justify-between px-2") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("boxes.contents.title") }
          span(class: "text-label-caps uppercase text-muted") { count_label }
        end
      end

      private

      #: () -> String
      def count_label
        if @unpacked
          I18n.t("boxes.contents.unpacked_count", count: @unpacked, total: @total)
        else
          I18n.t("boxes.contents.count", count: @total)
        end
      end
    end
  end
end

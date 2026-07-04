# frozen_string_literal: true

module Components
  module Unpacking
    # E3 — the dimmed "unpacked" section: a heading plus the tap-to-restore rows.
    # ALWAYS rendered (even when empty), kept out of view with the `hidden` class,
    # so a remove stream always has a stable target to replace when the first item
    # is unpacked — and the section reveals/hides itself as the list crosses the
    # empty boundary.
    class UnpackedSection < Components::Base
      ID = "unpacking-unpacked-section"

      #: (unpacked: untyped, move: untyped, box: untyped, editable: untyped) -> void
      def initialize(unpacked:, move:, box:, editable:)
        @unpacked = unpacked
        @move = move
        @box = box
        @editable = editable
      end

      #: () -> void
      def view_template
        classes = ["flex flex-col gap-stack-gap", ("hidden" if @unpacked.empty?)].compact.join(" ")
        section(id: ID, class: classes) do
          h2(class: "flex items-center gap-2 text-headline-md text-muted") do
            render Components::Icons::Check.new(css: "h-5 w-5")
            plain I18n.t("unpacking.unpacked_title")
          end
          div(class: "flex flex-col gap-stack-gap opacity-70") do
            @unpacked.each do |item|
              render Components::Unpacking::ItemRow.new(
                item:, move: @move, box: @box, variant: :unpacked, editable: @editable
              )
            end
          end
        end
      end
    end
  end
end

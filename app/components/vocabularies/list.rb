# frozen_string_literal: true

module Components
  module Vocabularies
    # D2 — the controlled-vocabulary value list (or its empty state). Stable id so
    # the controller can replace the whole list after a create/rename (the new or
    # renamed row lands at its sorted position, highlighted) or after the last
    # remove flips it to the empty state — always replacing this guaranteed-present
    # wrapper rather than appending to a maybe-absent rows container.
    class List < Components::Base
      ID = "vocab-list"

      #: (move: untyped, vocabulary: untyped, records: untyped, usage_counts: untyped, can_edit: untyped, ?highlight_id: untyped) -> void
      def initialize(move:, vocabulary:, records:, usage_counts:, can_edit:, highlight_id: nil)
        @move = move
        @vocabulary = vocabulary
        @records = records.to_a
        @usage_counts = usage_counts
        @can_edit = can_edit
        @highlight_id = highlight_id
      end

      #: () -> void
      def view_template
        div(id: ID) do
          @records.any? ? rows : empty_state
        end
      end

      private

      #: () -> untyped
      def rows
        div(class: "flex flex-col gap-stack-gap") do
          @records.each do |record|
            render Components::Vocabularies::Row.new(
              move: @move, vocabulary: @vocabulary, record: record,
              usage_count: @usage_counts[record.id].to_i, can_edit: @can_edit,
              highlight: record.id == @highlight_id
            )
          end
        end
      end

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: @vocabulary.icon,
          title: I18n.t("vocabularies.#{@vocabulary.kind}.empty_title"),
          description: I18n.t("vocabularies.#{@vocabulary.kind}.empty_description")
        )
      end
    end
  end
end

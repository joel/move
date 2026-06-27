# frozen_string_literal: true

module Views
  module Vocabularies
    # D2 — Manage categories / tags / rooms. One template for all three sibling
    # surfaces: a header, sibling tabs, an add form (admins, writable Move), and
    # a row list with inline rename + remove. Renders inside the AppLayout sidebar
    # shell. Stitch is dark-only; light comes from the Refined-Palette tokens.
    #
    # The add form, list and rows are extracted into stable-id Components so the
    # controller can stream create/rename/remove without a reload (#382); the
    # rename form is toggled open client-side (inline-edit), so even opening it
    # no longer navigates.
    class Index < Views::Base
      def initialize(move:, vocabulary:, records:, usage_counts:, can_edit:, new_record: nil)
        @move = move
        @vocabulary = vocabulary
        @records = records
        @usage_counts = usage_counts
        @can_edit = can_edit
        @new_record = new_record
      end

      def view_template
        header
        tabs
        if @can_edit
          render Components::Vocabularies::AddForm.new(
            move: @move, vocabulary: @vocabulary, record: @new_record || @vocabulary.model.new
          )
        end
        render Components::Vocabularies::List.new(
          move: @move, vocabulary: @vocabulary, records: @records,
          usage_counts: @usage_counts, can_edit: @can_edit
        )
      end

      private

      def kind = @vocabulary.kind

      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("vocabularies.#{kind}.title"),
          subtitle: I18n.t("vocabularies.#{kind}.subtitle")
        ) do
          if @can_edit
            render Components::Ui::Button.new(
              label: I18n.t("vocabularies.#{kind}.add"),
              icon: Components::Icons::Plus, href: "##{Components::Vocabularies::AddForm::ID}"
            )
          end
        end
      end

      # Sibling navigation across the three vocabularies (Categories | Tags |
      # Rooms). The active surface fills; the others are outlined links.
      def tabs
        nav(class: "flex gap-3 overflow-x-auto pb-1", aria_label: I18n.t("vocabularies.tabs_label")) do
          Vocabulary::KINDS.each do |k|
            a(href: move_vocabularies_path(@move, k), class: "flex-shrink-0") do
              render Components::Ui::Chip.new(
                label: I18n.t("vocabularies.#{k}.tab"),
                kind: Vocabulary.new(k).chip_kind, selected: k == kind
              )
            end
          end
        end
      end
    end
  end
end

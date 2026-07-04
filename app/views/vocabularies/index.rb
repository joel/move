# frozen_string_literal: true

module Views
  module Vocabularies
    # D2 — Manage rooms (the only managed vocabulary left). A header, an add form
    # (admins, writable Move), and a row list with inline rename + remove. Renders
    # inside the AppLayout sidebar shell. Stitch is dark-only; light comes from the
    # Refined-Palette tokens.
    #
    # The add form, list and rows are extracted into stable-id Components so the
    # controller can stream create/rename/remove without a reload (#382); the
    # rename form is toggled open client-side (inline-edit), so even opening it
    # no longer navigates.
    class Index < Views::Base
      #: (move: untyped, vocabulary: untyped, records: untyped, usage_counts: untyped, can_edit: untyped, ?new_record: untyped) -> void
      def initialize(move:, vocabulary:, records:, usage_counts:, can_edit:, new_record: nil)
        @move = move
        @vocabulary = vocabulary
        @records = records
        @usage_counts = usage_counts
        @can_edit = can_edit
        @new_record = new_record
      end

      #: () -> void
      def view_template
        header
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

      #: () -> untyped
      def kind = @vocabulary.kind

      #: () -> untyped
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
    end
  end
end

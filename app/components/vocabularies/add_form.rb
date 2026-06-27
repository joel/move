# frozen_string_literal: true

module Components
  module Vocabularies
    # D2 — the "add a value" card (admins, writable Move). Stable id so a rejected
    # create can stream the form back with its field error, and the reset-form
    # controller clears + refocuses it after a successful (streamed) add so the
    # next value can be typed straight away.
    class AddForm < Components::Base
      ID = "vocab-add"

      def initialize(move:, vocabulary:, record:)
        @move = move
        @vocabulary = vocabulary
        @record = record
      end

      def view_template
        render Components::Ui::Card.new(id: ID) do
          h3(class: "text-label-caps uppercase text-muted") do
            I18n.t("vocabularies.#{@vocabulary.kind}.add")
          end
          render Components::VocabularyForm.new(
            vocabulary: @vocabulary, record: @record,
            url: move_vocabularies_path(@move, @vocabulary.kind), method: :post,
            submit_label: I18n.t("vocabularies.form.add_submit"),
            form_data: { controller: "reset-form", action: "turbo:submit-end->reset-form#reset" }
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

module Components
  module Vocabularies
    # D2 — one controlled-vocabulary value row (category / tag / room): a display
    # panel (medallion, name, applies-to + usage meta, rename/remove actions) and
    # an inline edit form toggled client-side by the `inline-edit` Stimulus
    # controller — no GET reload to open it. Carries a stable per-record DOM id so
    # the controller can stream a rename in place or remove it without a reload.
    #
    # open: re-render with the edit form already open (a rejected rename, so the
    #   field error shows). highlight: just created/renamed — scroll + ring it.
    class Row < Components::Base
      include Phlex::Rails::Helpers::ButtonTo

      # @rbs skip
      def self.dom_id(record)
        "vocab-#{record.id}"
      end

      # record drives the display + stable id (always the persisted value).
      # edit_record drives the edit form's field values + errors; it defaults to
      # record, but a rejected rename passes the submitted (invalid) record so the
      # form shows what was typed + the error while the display stays persisted —
      # so canceling reveals the persisted name, never the abandoned/invalid one.

      # @rbs move: untyped
      # @rbs vocabulary: untyped
      # @rbs record: untyped
      # @rbs usage_count: untyped
      # @rbs can_edit: untyped
      # @rbs open: untyped
      # @rbs highlight: untyped
      # @rbs edit_record: untyped
      # @rbs return: void
      def initialize(move:, vocabulary:, record:, usage_count:, can_edit:,
                     open: false, highlight: false, edit_record: nil)
        @move = move
        @vocabulary = vocabulary
        @record = record
        @usage_count = usage_count
        @can_edit = can_edit
        @open = open
        @highlight = highlight
        @edit_record = edit_record || record
      end

      #: () -> void
      def view_template
        div(id: self.class.dom_id(@record), data: row_data,
            class: "rounded-card border border-card-border bg-card p-4") do
          div(data: { inline_edit_target: "display" }) { row_body }
          edit_panel if @can_edit
        end
      end

      private

      #: () -> untyped
      def kind = @vocabulary.kind

      #: () -> untyped
      def row_data
        controllers = []
        controllers << "inline-edit" if @can_edit
        controllers << "highlight" if @highlight
        return {} if controllers.empty?

        data = { controller: controllers.join(" ") }
        # The string "true" (not a Ruby boolean): Phlex renders `true` as a bare
        # `data-inline-edit-open-value` attribute, which Stimulus reads as false
        # (a Boolean value coerces via `=== "true"`), so the form wouldn't reopen.
        data[:inline_edit_open_value] = "true" if @can_edit && @open
        data
      end

      #: () -> untyped
      def edit_panel
        div(class: "hidden", data: { inline_edit_target: "form" }) do
          render Components::VocabularyForm.new(
            vocabulary: @vocabulary, record: @edit_record,
            url: move_vocabulary_path(@move, kind, @record), method: :patch,
            submit_label: I18n.t("vocabularies.form.save"),
            cancel_action: "inline-edit#cancel", compact: true,
            field_data: { inline_edit_target: "input" }
          )
        end
      end

      #: () -> untyped
      def row_body
        div(class: "flex items-center justify-between gap-4") do
          identity
          actions if @can_edit
        end
      end

      #: () -> untyped
      def identity
        div(class: "flex min-w-0 items-center gap-4") do
          medallion
          div(class: "flex min-w-0 flex-col gap-1") do
            span(class: "truncate text-headline-md text-text-warm") { @record.name }
            meta
          end
        end
      end

      #: () -> untyped
      def medallion
        div(class: "flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full " \
                   "#{Components::Ui::Chip::KINDS[@vocabulary.chip_kind]}") do
          render @vocabulary.icon.new(css: "h-6 w-6")
        end
      end

      #: () -> untyped
      def meta
        div(class: "flex flex-wrap items-center gap-2") do
          span(class: "text-body-md text-muted") do
            I18n.t("vocabularies.#{kind}.usage", count: @usage_count)
          end
        end
      end

      #: () -> untyped
      def actions
        div(class: "flex flex-shrink-0 items-center gap-1") do
          button(type: "button", data: { action: "inline-edit#edit" }, class: icon_button_class,
                 aria: { label: I18n.t("vocabularies.actions.rename", name: @record.name) }) do
            render Components::Icons::Pencil.new(css: "h-5 w-5")
          end
          remove_button
        end
      end

      # Removing an in-use value warns first (Turbo confirm); an unused value
      # deletes straight away. The confirm goes on the generated <form> (via
      # `form:`), the canonical place Turbo gates submission regardless of version.

      #: () -> untyped
      def remove_button
        opts = {
          method: :delete,
          class: "#{icon_button_class} hover:text-error",
          aria: { label: I18n.t("vocabularies.actions.remove", name: @record.name) }
        } #: Hash[Symbol, untyped]
        opts[:form] = { data: { turbo_confirm: I18n.t("vocabularies.#{kind}.remove_confirm", count: @usage_count) } } if @usage_count.positive?
        button_to(move_vocabulary_path(@move, kind, @record), **opts) do
          render Components::Icons::Trash.new(css: "h-5 w-5")
        end
      end

      #: () -> String
      def icon_button_class
        "inline-flex h-10 w-10 items-center justify-center rounded-full text-muted " \
          "transition hover:bg-surface-container-high hover:text-text-warm"
      end
    end
  end
end

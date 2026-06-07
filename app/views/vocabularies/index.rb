# frozen_string_literal: true

module Views
  module Vocabularies
    # D2 — Manage categories / tags / rooms. One template for all three sibling
    # surfaces: a header, sibling tabs, an add form (admins, writable Move), and
    # a row list with rename (inline) + remove (confirmed when in use). Renders
    # inside the AppLayout sidebar shell. Stitch is dark-only; light comes from
    # the Refined-Palette tokens.
    class Index < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, vocabulary:, records:, usage_counts:, can_edit:, editing: nil, new_record: nil)
        @move = move
        @vocabulary = vocabulary
        @records = records
        @usage_counts = usage_counts
        @can_edit = can_edit
        @editing = editing&.to_s
        @new_record = new_record
      end

      def view_template
        header
        tabs
        add_form if @can_edit
        @records.any? ? list : empty_state
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
              icon: Components::Icons::Plus, href: "#vocab-add"
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

      def add_form
        render Components::Ui::Card.new(id: "vocab-add") do
          h3(class: "text-label-caps uppercase text-muted") { I18n.t("vocabularies.#{kind}.add") }
          render Components::VocabularyForm.new(
            vocabulary: @vocabulary, record: @new_record,
            url: move_vocabularies_path(@move, kind), method: :post,
            submit_label: I18n.t("vocabularies.form.add_submit")
          )
        end
      end

      def list
        div(class: "flex flex-col gap-stack-gap") do
          @records.each { |record| row(record) }
        end
      end

      def row(record)
        div(id: "vocab-#{record.id}", class: "rounded-card border border-card-border bg-card p-4") do
          if @can_edit && @editing == record.id.to_s
            edit_form(record)
          else
            row_body(record)
          end
        end
      end

      def row_body(record)
        div(class: "flex items-center justify-between gap-4") do
          identity(record)
          actions(record) if @can_edit
        end
      end

      def identity(record)
        div(class: "flex min-w-0 items-center gap-4") do
          medallion
          div(class: "flex min-w-0 flex-col gap-1") do
            span(class: "truncate text-headline-md text-text-warm") { record.name }
            meta(record)
          end
        end
      end

      def medallion
        div(class: "flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-full " \
                   "#{Components::Ui::Chip::KINDS[@vocabulary.chip_kind]}") do
          render @vocabulary.icon.new(css: "h-6 w-6")
        end
      end

      def meta(record)
        div(class: "flex flex-wrap items-center gap-2") do
          if @vocabulary.applies_to?
            render Components::Ui::Chip.new(
              label: I18n.t("vocabularies.applies_to.#{record.applies_to}"), kind: :tag
            )
          end
          span(class: "text-body-md text-muted") { usage_label(record) }
        end
      end

      def usage_label(record)
        I18n.t("vocabularies.#{kind}.usage", count: @usage_counts[record.id].to_i)
      end

      def actions(record)
        div(class: "flex flex-shrink-0 items-center gap-1") do
          a(
            href: move_vocabularies_path(@move, kind, edit: record.id, anchor: "vocab-#{record.id}"),
            aria_label: I18n.t("vocabularies.actions.rename", name: record.name),
            class: icon_button_class
          ) { render Components::Icons::Pencil.new(css: "h-5 w-5") }
          remove_button(record)
        end
      end

      # Removing an in-use value warns first (Turbo confirm); an unused value
      # deletes straight away. Detachment itself happens server-side.
      def remove_button(record)
        count = @usage_counts[record.id].to_i
        opts = {
          method: :delete,
          class: "#{icon_button_class} hover:text-error",
          aria_label: I18n.t("vocabularies.actions.remove", name: record.name)
        }
        opts[:data] = { turbo_confirm: I18n.t("vocabularies.#{kind}.remove_confirm", count: count) } if count.positive?
        button_to(move_vocabulary_path(@move, kind, record), **opts) do
          render Components::Icons::Trash.new(css: "h-5 w-5")
        end
      end

      def edit_form(record)
        render Components::VocabularyForm.new(
          vocabulary: @vocabulary, record: record,
          url: move_vocabulary_path(@move, kind, record), method: :patch,
          submit_label: I18n.t("vocabularies.form.save"),
          cancel_href: move_vocabularies_path(@move, kind), compact: true
        )
      end

      def icon_button_class
        "inline-flex h-10 w-10 items-center justify-center rounded-full text-muted " \
          "transition hover:bg-surface-container-high hover:text-text-warm"
      end

      def empty_state
        render Components::Ui::EmptyState.new(
          icon: @vocabulary.icon,
          title: I18n.t("vocabularies.#{kind}.empty_title"),
          description: I18n.t("vocabularies.#{kind}.empty_description")
        )
      end
    end
  end
end

# frozen_string_literal: true

module Components
  # Shared item form fields for B3 (manual add) and C3 (detail/edit). Lightweight
  # per the spec: name, category (selection-only), quantity, fragile, tags
  # (selection-only) — no value fields. `models` is the Rails-nested model array
  # ([move, box, item] for create, [move, item] for update) so form_with derives
  # the right URL + verb. The C3 Move/Remove controls are separate forms rendered
  # by the view, not part of this edit form.
  class ItemForm < Components::Base
    include Phlex::Rails::Helpers::FormWith

    def initialize(models:, item:, categories:, tags:, submit_label: nil, cancel_href: nil,
                   autosave: false, source_media_id: nil)
      @models = models
      @item = item
      @categories = categories
      @tags = tags
      @submit_label = submit_label
      @cancel_href = cancel_href
      # When present, binds the new item to a captured photo (recovery flow): the
      # manual add resolves an orphaned photo by attaching it as source_media.
      @source_media_id = source_media_id
      # C3 auto-saves: every field change submits the whole form (the form-level
      # `change->auto-submit#submit` action), so there is no submit button. B3
      # (manual add) keeps the button — a not-yet-created record can't auto-save.
      @autosave = autosave
    end

    def view_template
      form_with(model: @models, class: "flex flex-col gap-6", **form_attrs) do |form|
        input(type: "hidden", name: "item[source_media_id]", value: @source_media_id) if @source_media_id
        render_errors if @item.errors.any?
        name_field
        category_and_quantity
        fragile_toggle
        tags_field
        footer(form) unless @autosave
      end
    end

    private

    def form_attrs
      return {} unless @autosave

      { data: { controller: "auto-submit", action: "change->auto-submit#submit" } }
    end

    def name_field
      render Components::Ui::Field.new(
        name: "item[name]", label: I18n.t("items.form.name"),
        value: @item.name, placeholder: I18n.t("items.form.name_placeholder"),
        error: @item.errors[:name].first
      )
    end

    def category_and_quantity
      div(class: "grid grid-cols-1 gap-5 sm:grid-cols-2") do
        render Components::Ui::Select.new(
          name: "item[category_id]", label: I18n.t("items.form.category"),
          options: category_options, selected: @item.category_id
        )
        div(class: "flex flex-col gap-2") do
          span(class: "text-label-caps uppercase text-muted") { I18n.t("items.form.quantity") }
          render Components::Ui::QuantityAdjuster.new(
            name: "item[quantity]", value: @item.quantity || 1, min: 1
          )
        end
      end
    end

    def category_options
      [[I18n.t("items.form.category_blank"), ""]] + @categories.map { |c| [c.name, c.id] }
    end

    def fragile_toggle
      div(class: "flex items-center justify-between rounded-card border border-card-border bg-card px-4 py-3") do
        span(class: "flex items-center gap-2 text-body-md text-text-warm") do
          render Components::Icons::Alert.new(css: "h-5 w-5 text-secondary")
          plain I18n.t("items.form.fragile")
        end
        toggle_switch
      end
    end

    def toggle_switch
      label(class: "relative inline-flex cursor-pointer items-center") do
        input(type: "hidden", name: "item[fragile]", value: "0")
        input(
          type: "checkbox", name: "item[fragile]", value: "1", checked: @item.fragile,
          class: "peer sr-only"
        )
        div(
          class: "h-6 w-11 rounded-full bg-surface-container-highest transition-colors " \
                 "peer-checked:bg-accent-sage"
        )
        div(
          class: "absolute left-1 top-1 h-4 w-4 rounded-full bg-white transition " \
                 "peer-checked:translate-x-5"
        )
      end
    end

    def tags_field
      div(class: "flex flex-col gap-2") do
        span(class: "text-label-caps uppercase text-muted") { I18n.t("items.form.tags") }
        @tags.any? ? tag_choices : tags_empty
      end
    end

    def tag_choices
      div(class: "flex flex-wrap gap-2") do
        # Empty value so deselecting every tag still submits the array (clears).
        input(type: "hidden", name: "item[tag_ids][]", value: "")
        @tags.each { |tag| tag_choice(tag) }
      end
    end

    def tag_choice(tag)
      label(class: "cursor-pointer") do
        input(
          type: "checkbox", name: "item[tag_ids][]", value: tag.id,
          checked: @item.tags.include?(tag), class: "peer sr-only"
        )
        span(
          class: "inline-flex items-center rounded-full px-3 py-1 text-label-caps uppercase " \
                 "bg-secondary/15 text-secondary transition " \
                 "peer-checked:bg-secondary peer-checked:text-on-secondary"
        ) { tag.name }
      end
    end

    def tags_empty
      p(class: "text-body-md text-on-surface-variant") { I18n.t("items.form.tags_empty") }
    end

    def footer(form)
      div(class: "mt-2 flex flex-wrap items-center justify-end gap-3") do
        if @cancel_href
          render Components::Ui::Button.new(
            label: I18n.t("items.form.cancel"), variant: :ghost, href: @cancel_href
          )
        end
        form.submit @submit_label, class: button_classes
      end
    end

    def button_classes
      "inline-flex items-center justify-center gap-2 rounded-full px-6 py-3 text-sm " \
        "font-bold transition select-none active:scale-[0.98] bg-accent-sage text-page hover:opacity-90"
    end

    def render_errors
      div(class: "rounded-card bg-[var(--ha-error-container)] px-5 py-4 text-body-md text-error") do
        h2(class: "font-semibold") { I18n.t("items.form.errors", count: @item.errors.count) }
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @item.errors.each { |error| li { error.full_message } }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Components
  # Shared item form for B3 (manual add) and C3 (detail/edit). An item is just a
  # name now (category/tags/quantity/fragile all removed across the simplification
  # epic). `models` is the Rails-nested model array ([move, box, item] for create,
  # [move, item] for update) so form_with derives the right URL + verb. The C3
  # Move/Remove controls are separate forms rendered by the view.
  class ItemForm < Components::Base
    include Phlex::Rails::Helpers::FormWith

    def initialize(models:, item:, submit_label: nil, cancel_href: nil,
                   autosave: false, source_media_id: nil)
      @models = models
      @item = item
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

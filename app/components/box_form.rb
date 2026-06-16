# frozen_string_literal: true

module Components
  # A2 — Add box form. Number is optional (auto-assigned when blank); room is a
  # free-typed name resolved against the per-Move vocabulary; dimensions are
  # optional. Posts to the Move-nested boxes route.
  class BoxForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    def initialize(move:, box:, rooms:, submit_label: nil, dimension_presets: [])
      @move = move
      @box = box
      @rooms = rooms
      @submit_label = submit_label || I18n.t("boxes.form.submit")
      @dimension_presets = dimension_presets
    end

    def view_template
      # Stimulus host so a "reuse dimensions" chip can fill the L/W/H inputs.
      form_with(model: [@move, @box], class: "flex flex-col gap-5",
                data: { controller: "dimension-presets" }) do |form|
        render_errors if @box.errors.any?

        field(form, :number, I18n.t("boxes.form.number"), optional: true,
                                                          placeholder: I18n.t("boxes.form.number_placeholder"))
        room_field(form)
        reuse_dimensions
        dimensions(form)
        description_field(form)

        div(class: "mt-2 flex flex-wrap gap-3") do
          form.submit @submit_label, class: "ha-button ha-button-primary"
        end
      end
    end

    private

    def room_field(form)
      div(class: "flex flex-col gap-2") do
        form.label :room_name, label_text(I18n.t("boxes.form.room"), optional: true),
                   class: "text-label-caps uppercase text-muted"
        form.text_field :room_name, list: "box-rooms", placeholder: I18n.t("boxes.form.room_placeholder"),
                                    class: "ha-input"
        datalist(id: "box-rooms") do
          @rooms.each { |room| option(value: room.name) }
        end
      end
    end

    # A horizontally-scrollable row of "reuse dimensions" chips — only shown when
    # this Move already has boxes with complete dimensions. Tapping a chip fills
    # the L/W/H inputs (weight is left alone; it varies per box).
    def reuse_dimensions
      return if @dimension_presets.blank?

      div(class: "flex flex-col gap-2") do
        span(class: "text-label-caps uppercase text-muted") { I18n.t("boxes.form.reuse_dimensions") }
        div(class: "-mx-1 flex gap-3 overflow-x-auto scrollbar-hide px-1 py-1") do
          @dimension_presets.each { |preset| dimension_chip(preset) }
        end
      end
    end

    def dimension_chip(preset)
      button(
        type: "button", class: "ha-dim-chip", "aria-pressed": preset_selected?(preset).to_s,
        data: {
          action: "dimension-presets#apply", dimension_presets_target: "chip",
          length: format_dim(preset[:length_cm]),
          width: format_dim(preset[:width_cm]),
          height: format_dim(preset[:height_cm])
        }
      ) do
        span(class: "text-body-md") { dimension_label(preset) }
        span(class: "ha-dim-chip-count") { "· #{preset[:count]}" } if preset[:count].to_i > 1
      end
    end

    # "40 × 30 × 25 cm" — trailing zeros trimmed so 40.00 reads as 40.
    def dimension_label(preset)
      I18n.t(
        "boxes.form.dimension_format",
        length: format_dim(preset[:length_cm]),
        width: format_dim(preset[:width_cm]),
        height: format_dim(preset[:height_cm])
      )
    end

    def format_dim(value)
      number = value.to_d
      number.frac.zero? ? number.to_i.to_s : number.to_s("F")
    end

    # Pre-press the chip matching the box's current dimensions (edit form).
    def preset_selected?(preset)
      Box::DIMENSIONS.all? { |dim| @box[dim].present? && @box[dim] == preset[dim] }
    end

    def dimensions(form)
      div(class: "grid grid-cols-2 gap-4 sm:grid-cols-4") do
        number_field(form, :length_cm, I18n.t("boxes.form.length_cm"), target: "length")
        number_field(form, :width_cm, I18n.t("boxes.form.width_cm"), target: "width")
        number_field(form, :height_cm, I18n.t("boxes.form.height_cm"), target: "height")
        number_field(form, :weight_kg, I18n.t("boxes.form.weight_kg"))
      end
    end

    # Optional contents description. A ✨ "Suggest with AI" button (wired to the
    # ai-suggest Stimulus controller) appears only once the box exists and holds
    # items — there's nothing to summarise on a brand-new, empty box.
    def description_field(form)
      attrs = suggestable? ? { controller: "ai-suggest", ai_suggest_url_value: suggest_url } : {}
      div(class: "flex flex-col gap-2", data: attrs) do
        div(class: "flex items-end justify-between gap-3") do
          form.label :description, label_text(I18n.t("boxes.form.description"), optional: true),
                     class: "text-label-caps uppercase text-muted"
          suggest_button if suggestable?
        end
        form.text_area :description, rows: 3, placeholder: I18n.t("boxes.form.description_placeholder"),
                                     class: "ha-input resize-none",
                                     data: (suggestable? ? { ai_suggest_target: "field" } : {})
      end
    end

    def suggest_button
      button(
        type: "button",
        class: "inline-flex items-center gap-1.5 rounded-full bg-accent-sage/10 px-3 py-1.5 " \
               "text-sm font-semibold text-accent-sage transition hover:bg-accent-sage/20 " \
               "disabled:opacity-50 disabled:pointer-events-none",
        data: { action: "ai-suggest#suggest", ai_suggest_target: "button" }
      ) do
        render Components::Icons::Sparkles.new(css: "h-[18px] w-[18px]")
        span(data: { ai_suggest_target: "buttonLabel", loading: I18n.t("boxes.form.generating") }) do
          I18n.t("boxes.form.suggest")
        end
      end
    end

    def suggestable?
      @box.persisted? && @box.item_count.positive?
    end

    def suggest_url
      description_suggestion_move_box_path(@move, @box)
    end

    def field(form, name, text, optional: false, placeholder: nil)
      div(class: "flex flex-col gap-2") do
        form.label name, label_text(text, optional: optional), class: "text-label-caps uppercase text-muted"
        form.text_field name, placeholder: placeholder, class: "ha-input"
      end
    end

    def number_field(form, name, text, target: nil)
      div(class: "flex flex-col gap-2") do
        form.label name, text, class: "text-label-caps uppercase text-muted"
        data = target ? { dimension_presets_target: target } : {}
        form.number_field name, step: "0.01", min: "0", class: "ha-input", data: data
      end
    end

    def label_text(text, optional: false)
      optional ? "#{text} · #{I18n.t("boxes.form.optional")}" : text
    end

    def render_errors
      div(class: "rounded-card bg-[var(--ha-error-container)] px-5 py-4 text-body-md text-error") do
        h2(class: "font-semibold") { plain I18n.t("boxes.form.errors", count: @box.errors.count) }
        ul(class: "mt-2 list-disc space-y-1 pl-5") do
          @box.errors.each { |error| li { error.full_message } }
        end
      end
    end
  end
end

# frozen_string_literal: true

module Components
  # A2 — Add box form. Number is optional (auto-assigned when blank); room is a
  # free-typed name resolved against the per-Move vocabulary; dimensions are
  # optional. Posts to the Move-nested boxes route.
  class BoxForm < Components::Base
    include Phlex::Rails::Helpers::FormWith
    include Phlex::Rails::Helpers::Pluralize

    def initialize(move:, box:, rooms:)
      @move = move
      @box = box
      @rooms = rooms
    end

    def view_template
      form_with(model: [@move, @box], class: "flex flex-col gap-5") do |form|
        render_errors if @box.errors.any?

        field(form, :number, I18n.t("boxes.form.number"), optional: true,
                                                          placeholder: I18n.t("boxes.form.number_placeholder"))
        room_field(form)
        dimensions(form)

        div(class: "mt-2 flex flex-wrap gap-3") do
          form.submit I18n.t("boxes.form.submit"), class: "ha-button ha-button-primary"
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

    def dimensions(form)
      div(class: "grid grid-cols-2 gap-4 sm:grid-cols-4") do
        number_field(form, :length_cm, I18n.t("boxes.form.length_cm"))
        number_field(form, :width_cm, I18n.t("boxes.form.width_cm"))
        number_field(form, :height_cm, I18n.t("boxes.form.height_cm"))
        number_field(form, :weight_kg, I18n.t("boxes.form.weight_kg"))
      end
    end

    def field(form, name, text, optional: false, placeholder: nil)
      div(class: "flex flex-col gap-2") do
        form.label name, label_text(text, optional: optional), class: "text-label-caps uppercase text-muted"
        form.text_field name, placeholder: placeholder, class: "ha-input"
      end
    end

    def number_field(form, name, text)
      div(class: "flex flex-col gap-2") do
        form.label name, text, class: "text-label-caps uppercase text-muted"
        form.number_field name, step: "0.01", min: "0", class: "ha-input"
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

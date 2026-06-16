# frozen_string_literal: true

module Views
  module Boxes
    # B1 — "Describe before sealing" modal frame. Lazy-loaded into the box-detail
    # dialog (turbo-frame :seal_box) when the user seals a box that has items but
    # no description. The contents description is auto-proposed server-side; the
    # form persists it atomically with the seal (PATCH transition, to: sealed).
    # Submitting breaks out to the top frame so the redirect to the box detail is
    # a full-page visit (which also dismisses the dialog).
    class Seal < Views::Base
      include Phlex::Rails::Helpers::FormWith
      include Phlex::Rails::Helpers::ButtonTo

      register_element :turbo_frame

      def initialize(move:, box:, suggestion: "")
        @move = move
        @box = box
        @suggestion = suggestion.to_s
      end

      def view_template
        turbo_frame(id: "seal_box") do
          div(class: "flex flex-col gap-stack-gap") do
            heading
            describe_form
            seal_without
          end
        end
      end

      private

      def heading
        div(class: "flex items-start justify-between gap-3") do
          div do
            h2(class: "text-headline-md text-text-warm") { I18n.t("boxes.seal.title") }
            p(class: "mt-1 text-body-md text-muted") { I18n.t("boxes.seal.subtitle") }
          end
          button(
            type: "button", aria_label: I18n.t("boxes.seal.close"),
            class: "rounded-full p-1 text-muted transition hover:text-text-warm",
            data: { action: "modal#close" }
          ) { render Components::Icons::Close.new(css: "h-5 w-5") }
        end
      end

      # The describe-and-seal form. data-turbo-frame=_top so the success redirect
      # navigates the whole page instead of trying to swap this frame.
      def describe_form
        form_with(url: transition_move_box_path(@move, @box), method: :patch, scope: :box,
                  data: { turbo_frame: "_top" }, class: "flex flex-col gap-2") do |form|
          input(type: "hidden", name: "to", value: "sealed")
          form.text_area :description, rows: 3, value: @suggestion,
                                       class: "ha-input resize-none",
                                       placeholder: I18n.t("boxes.seal.placeholder")
          regenerate
          div(class: "mt-4") do
            form.submit I18n.t("boxes.seal.confirm"), class: "ha-button ha-button-primary w-full"
          end
        end
      end

      # Re-requests this frame, forcing a fresh suggestion (overwrites any manual
      # edit — that's the point of "regenerate").
      def regenerate
        div(class: "flex justify-end") do
          a(
            # turbo_prefetch "false" (string — Phlex drops a boolean false attr) so
            # hovering Regenerate can't fire a quota-spending AI suggestion before
            # the click, then again on click.
            href: seal_move_box_path(@move, @box, regenerate: 1),
            data: { turbo_frame: "seal_box", turbo_prefetch: "false" },
            class: "inline-flex items-center gap-1 text-body-md text-accent-sage " \
                   "transition hover:opacity-80"
          ) do
            render Components::Icons::Sparkles.new(css: "h-[18px] w-[18px]")
            plain I18n.t("boxes.seal.regenerate")
          end
        end
      end

      # Seal with no description — a separate PATCH that sends no box[description],
      # so the seal proceeds and nothing is written to the column.
      def seal_without
        button_to(
          I18n.t("boxes.seal.skip"), transition_move_box_path(@move, @box),
          method: :patch, params: { to: "sealed" },
          form: { data: { turbo_frame: "_top" } },
          class: "w-full rounded-full px-6 py-3 text-sm font-bold text-muted " \
                 "transition hover:bg-surface-container-high"
        )
      end
    end
  end
end

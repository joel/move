# frozen_string_literal: true

module Views
  module Insurance
    # #702 — the Insurance hub: two export cards whose copy carries the privacy
    # distinction. The declaration (sanitized: themes only, no locations, no
    # photos) is a plain GET any member may use; the claim dossier (per box,
    # with photos) renders only for admins (no dead-end 403) and POSTs an async
    # generation run. Reached from the Menu.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      # @rbs move: untyped
      # @rbs dossier_allowed: untyped
      # @rbs item_count: untyped
      # @rbs return: void
      def initialize(move:, dossier_allowed:, item_count:)
        @move = move
        @dossier_allowed = dossier_allowed
        # In_box item count (controller-computed): zero renders the empty state
        # instead of two export cards that could only produce a useless PDF or
        # an alert bounce (ux rule 5 — the labels-hub precedent).
        @item_count = item_count
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("insurance.title"),
            subtitle: I18n.t("insurance.subtitle")
          )
          if @item_count.zero?
            empty_state
          else
            declaration_card
            dossier_card if @dossier_allowed
          end
        end
      end

      private

      #: () -> untyped
      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Shield,
          title: I18n.t("insurance.empty.title"),
          description: I18n.t("insurance.empty.description")
        )
      end

      #: () -> untyped
      def declaration_card
        div(class: "ha-card p-6 flex flex-col gap-3") do
          h2(class: "text-headline-sm text-text-warm") { I18n.t("insurance.declaration.title") }
          p(class: "text-body-md text-muted") { I18n.t("insurance.declaration.description") }
          div do
            # data-turbo=false: the link returns a PDF (not HTML) — Turbo Drive
            # would intercept the navigation and fetch it into the void instead
            # of letting the browser render/save it.
            render Components::Ui::Button.new(
              label: I18n.t("insurance.declaration.download"),
              href: move_insurance_declaration_path(@move),
              data: { turbo: "false" }
            )
          end
        end
      end

      #: () -> untyped
      def dossier_card
        div(class: "ha-card p-6 flex flex-col gap-3") do
          h2(class: "text-headline-sm text-text-warm") { I18n.t("insurance.dossier.title") }
          p(class: "text-body-md text-muted") { I18n.t("insurance.dossier.description") }
          div do
            # button_to needs a form, so it can't render Ui::Button — it borrows
            # the component's class recipe instead of forking it (#702).
            button_to(
              I18n.t("insurance.dossier.generate"),
              move_insurance_dossier_runs_path(@move),
              method: :post,
              class: Components::Ui::Button.classes
            )
          end
        end
      end
    end
  end
end

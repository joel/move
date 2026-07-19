# frozen_string_literal: true

module Views
  module InsuranceDossierRuns
    # #702 — live progress page for a claim-dossier run, mirroring the label
    # print run page (#303). Subscribes to the run's progress stream (signed
    # from the run's uuid — the auth boundary) and renders the status component,
    # which the generation job replaces in place as it advances and again when
    # the PDF is ready to download. No polling.
    class Show < Views::Base
      include Phlex::Rails::Helpers::Routes
      include Phlex::Rails::Helpers::TurboStreamFrom

      #: (move: untyped, run: untyped) -> void
      def initialize(move:, run:)
        @move = move
        @run = run
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          turbo_stream_from(@run, :progress)
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("insurance.run.title"),
            subtitle: I18n.t("insurance.run.subtitle",
                             boxes: @run.total_count, items: @run.item_count)
          )
          div(class: "ha-card p-6 flex flex-col gap-stack-gap") do
            render Components::Ui::InsuranceDossierStatus.new(run: @run)
          end
          a(href: move_insurance_path(@move),
            class: "text-body-md font-semibold text-on-surface-variant transition hover:text-text-warm") do
            plain I18n.t("insurance.run.back")
          end
        end
      end
    end
  end
end

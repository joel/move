# frozen_string_literal: true

module Views
  module Recoveries
    # The status/action region of the photo recovery screen — rendered standalone
    # by the recognition poller (captures#session pattern) so a re-run updates in
    # place. Carries `data-pending` (1 while a run is in flight) so the poller knows
    # when to stop. Branches: recovered → "view items"; in flight → processing;
    # failed → reason + Retry + Add item; zero-detection → Add item only.
    class State < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      def initialize(move:, box:, media:, run:, editable: false, recovered: false)
        @move = move
        @box = box
        @media = media
        @run = run
        @editable = editable
        @recovered = recovered
      end

      def view_template
        div(data: { pending: pending }) do
          render Components::Ui::Card.new(padding: "p-6") do
            @recovered ? recovered_body : status_body
          end
        end
      end

      private

      # While a (re-)run is queued/processing the poller keeps refreshing; any
      # terminal/recovered state stops it.
      def pending
        return 0 if @recovered

        @run && %w[queued processing].include?(@run.status) ? 1 : 0
      end

      def status_body
        if in_flight?
          processing_body
        elsif @run&.failed?
          failed_body
        else
          empty_body
        end
      end

      def in_flight?
        @run && %w[queued processing].include?(@run.status)
      end

      def processing_body
        render Components::Ui::RecognitionState.new(state: :processing)
        heading(I18n.t("recoveries.processing.title"))
        subtitle(I18n.t("recoveries.processing.subtitle"))
      end

      def failed_body
        render Components::Ui::RecognitionState.new(state: :failed)
        heading(I18n.t("recoveries.failed.title"))
        render Components::Ui::RecognitionErrorCaption.new(run: @run)
        actions(with_retry: true)
      end

      def empty_body
        heading(I18n.t("recoveries.empty.title"))
        subtitle(I18n.t("recoveries.empty.subtitle"))
        actions(with_retry: false)
      end

      def recovered_body
        render Components::Ui::RecognitionState.new(state: :succeeded)
        heading(I18n.t("recoveries.recovered.title"))
        subtitle(I18n.t("recoveries.recovered.subtitle"))
        a(
          href: move_box_review_photo_path(@move, @box, @media), data: { turbo_prefetch: "false" },
          class: primary_classes
        ) { plain I18n.t("recoveries.recovered.view_items") }
      end

      # Retry is offered only for a failed run (matches RecognitionRuns::Retry's
      # guard); a zero-detection photo gets manual add only — re-running finds
      # nothing again. Both actions require an editor on a writable Move.
      def actions(with_retry:)
        return unless @editable

        div(class: "mt-5 flex flex-col gap-3") do
          retry_button if with_retry
          add_item_link
        end
      end

      def retry_button
        button_to(
          I18n.t("recoveries.actions.retry"),
          move_box_recovery_photo_retry_path(@move, @box, @media),
          method: :post, class: primary_classes
        )
      end

      def add_item_link
        a(
          href: new_move_box_item_path(@move, @box, source_media_id: @media.id),
          class: secondary_classes
        ) { plain I18n.t("recoveries.actions.add_item") }
      end

      def heading(text)
        h2(class: "mt-4 text-headline-md text-text-warm") { text }
      end

      def subtitle(text)
        p(class: "mt-1 text-body-md text-muted") { text }
      end

      def primary_classes
        "inline-flex w-full items-center justify-center gap-2 rounded-full bg-accent-sage " \
          "px-6 py-3 text-sm font-bold text-page transition hover:opacity-90 active:scale-[0.98]"
      end

      def secondary_classes
        "inline-flex w-full items-center justify-center gap-2 rounded-full border border-card-border " \
          "px-6 py-3 text-sm font-bold text-text-warm transition hover:border-accent-sage"
      end
    end
  end
end

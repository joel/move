# frozen_string_literal: true

module Views
  module Captures
    # The "Session" panel: this box's recent captures with live recognition state.
    # Re-rendered by the polled `captures#session` endpoint; the root carries
    # `data-pending` so the Stimulus poller knows when to stop.
    class SessionPanel < Views::Base
      RUN_TO_STATE = {
        "queued" => :queued, "processing" => :processing,
        "succeeded" => :succeeded, "partially_succeeded" => :succeeded, "failed" => :failed
      }.freeze

      def initialize(box:, media:)
        @box = box
        @media = media
      end

      def view_template
        div(data: { pending: pending_count }, class: "flex flex-col gap-4") do
          @media.any? ? list : empty_state
        end
      end

      private

      def pending_count
        @box.recognition_runs.where(status: %w[queued processing]).count
      end

      def list
        @media.each { |media| row(media) }
      end

      def row(media)
        run = media.recognition_runs.max_by(&:created_at)
        div(class: "flex items-center gap-3 rounded-xl border border-card-border bg-surface-container p-3") do
          thumb(media)
          div(class: "flex flex-1 flex-col gap-1") do
            state_badge(run)
            items_found(run)
            retry_button(media) if run&.failed?
          end
        end
      end

      def thumb(media)
        div(class: "flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          if media.image.attached?
            img(
              src: view_context.rails_storage_proxy_path(media.image),
              class: "h-full w-full object-cover", alt: "", loading: "lazy"
            )
          else
            render Components::Icons::Camera.new(css: "h-6 w-6")
          end
        end
      end

      def state_badge(run)
        return span(class: "text-label-caps uppercase text-muted") { I18n.t("ui.states.queued") } if run.nil?

        render Components::Ui::RecognitionState.new(state: RUN_TO_STATE.fetch(run.status, :queued))
      end

      # One photo can yield many items: surface the detection count once a run
      # succeeds so the capture session reflects "many items per photo", not 1:1.
      def items_found(run)
        return unless run && %w[succeeded partially_succeeded].include?(run.status)

        count = run.metadata["item_count"]
        return if count.nil?

        span(class: "text-label-caps uppercase text-muted") do
          I18n.t("captures.session.items_found", count: count.to_i)
        end
      end

      def retry_button(media)
        button_to(
          I18n.t("ui.buttons.retry"),
          view_context.move_box_capture_retry_path(@box.move_id, @box, media_id: media.id),
          method: :post,
          class: "self-start rounded-full bg-error px-3 py-1 text-label-caps uppercase text-on-error"
        )
      end

      def empty_state
        p(class: "text-body-md text-muted") { I18n.t("captures.session.empty") }
      end
    end
  end
end

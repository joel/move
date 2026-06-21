# frozen_string_literal: true

module Views
  module Captures
    # The "Items" panel: this box's recent captures with live recognition state.
    # Broadcast over ActionCable as each run advances (#241 — Captures::
    # SessionBroadcastSubscriber); the stable root id is the Turbo Stream replace
    # target. Once a photo's run succeeds it expands into one tappable row per
    # recognised item (→ Item Detail); photos still queued/processing/failed render
    # as a single status row.
    class SessionPanel < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "capture-session-panel"

      RUN_TO_STATE = {
        "queued" => :queued, "processing" => :processing,
        "succeeded" => :succeeded, "partially_succeeded" => :succeeded, "failed" => :failed
      }.freeze

      def initialize(box:, media:, items_by_media: {})
        @box = box
        @media = media
        @items_by_media = items_by_media
      end

      def view_template
        div(id: ID, class: "flex flex-col gap-4") do
          @media.any? ? list : empty_state
        end
      end

      private

      def list
        @media.each { |media| rows(media) }
      end

      # A succeeded photo becomes one tappable row per item; otherwise a single
      # status row (queued / recognising / failed).
      def rows(media)
        run = media.recognition_runs.max_by(&:created_at)
        items = @items_by_media[media.id]
        if succeeded?(run) && items&.any?
          items.each { |item| item_row(media, item) }
        else
          status_row(media, run)
        end
      end

      def succeeded?(run)
        run && %w[succeeded partially_succeeded].include?(run.status)
      end

      # Tappable recognised-item row → Item Detail, so a wrong category/name can be
      # fixed without leaving the capture flow.
      def item_row(media, item)
        a(
          href: view_context.move_item_path(@box.move, item),
          class: "flex items-center gap-3 rounded-xl border border-card-border " \
                 "bg-surface-container p-3 transition hover:border-accent-sage " \
                 "hover:bg-surface-container-high"
        ) do
          thumb(media)
          div(class: "flex min-w-0 flex-1 flex-col gap-1") do
            span(class: "truncate text-body-md font-bold text-text-warm") { item_label(item) }
            chips(item)
          end
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 shrink-0 text-muted")
        end
      end

      def item_label(item)
        item.quantity.to_i > 1 ? "#{item.name} ×#{item.quantity}" : item.name
      end

      def chips(item)
        return unless item.category || item.fragile?

        div(class: "flex flex-wrap gap-1.5") do
          render Components::Ui::Chip.new(label: item.category.name, kind: :room) if item.category
          render Components::Ui::Chip.new(label: I18n.t("boxes.item.fragile"), kind: :tag) if item.fragile?
        end
      end

      def status_row(media, run)
        div(class: "flex items-center gap-3 rounded-xl border border-card-border bg-surface-container p-3") do
          thumb(media)
          div(class: "flex flex-1 flex-col gap-1") do
            state_badge(run)
            render Components::Ui::RecognitionErrorCaption.new(run:) if run&.failed?
            retry_button(media) if run&.failed?
          end
        end
      end

      def thumb(media)
        div(class: "flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          if media.image.attached?
            img(
              src: view_context.rails_storage_proxy_path(media.image.variant(:thumb)),
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

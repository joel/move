# frozen_string_literal: true

module Views
  module Captures
    # The capture panel: this box's recent captures with live recognition state.
    # Broadcast over ActionCable as each run advances (#241 — Captures::
    # SessionBroadcastSubscriber); the stable root id is the Turbo Stream replace
    # target. Capture is photo-first (D3): a succeeded photo is ONE card showing
    # its recognised names as chips, tapping into the per-photo detail (C2);
    # photos still queued/processing/failed render as a single status row.
    class SessionPanel < Views::Base
      include Phlex::Rails::Helpers::ButtonTo

      ID = "capture-session-panel"
      CHIP_CAP = 4 # name chips shown per photo card before collapsing to "+N more"

      RUN_TO_STATE = {
        "queued" => :queued, "processing" => :processing,
        "succeeded" => :succeeded, "partially_succeeded" => :succeeded, "failed" => :failed
      }.freeze

      #: (box: untyped, media: untyped, ?items_by_media: untyped) -> void
      def initialize(box:, media:, items_by_media: {})
        @box = box
        @media = media
        @items_by_media = items_by_media
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-4") do
          header_row
          @media.any? ? list : empty_state
        end
      end

      private

      # Title + live count live INSIDE the replaced target (#545/#546) so both the
      # capture Turbo response and the ActionCable broadcast refresh the count —
      # a header outside the target would go stale until a full reload.

      #: () -> untyped
      def header_row
        div(class: "flex items-center justify-between px-1") do
          h3(class: "text-headline-md text-text-warm") { I18n.t("captures.session.title") }
          span(class: "text-label-caps uppercase text-muted") do
            I18n.t("captures.session.count", count: @media.size)
          end
        end
      end

      #: () -> untyped
      def list
        @media.each { |media| rows(media) }
      end

      # A succeeded photo becomes one card with its recognised names as chips;
      # otherwise a single status row (queued / recognising / failed).

      #: (untyped media) -> untyped
      def rows(media)
        run = media.recognition_runs.max_by(&:created_at)
        items = @items_by_media[media.id]
        if succeeded?(run) && items&.any?
          photo_card(media, items)
        else
          status_row(media, run)
        end
      end

      #: (untyped run) -> bool
      def succeeded?(run)
        run && %w[succeeded partially_succeeded].include?(run.status)
      end

      # Photo-first card: the photo + its recognised names as chips, tapping into
      # the per-photo detail (C2) where a wrong name can be fixed — no separate
      # per-item rows.

      #: (untyped media, untyped items) -> untyped
      def photo_card(media, items)
        a(
          href: view_context.move_box_review_photo_path(@box.move, @box, media_id: media.id),
          class: "flex items-center gap-3 rounded-xl border border-card-border " \
                 "bg-surface-container p-3 transition hover:border-accent-sage " \
                 "hover:bg-surface-container-high"
        ) do
          thumb(media)
          div(class: "flex min-w-0 flex-1 flex-wrap gap-1") do
            items.first(CHIP_CAP).each { |item| name_chip(item.name) }
            name_chip(I18n.t("captures.session.more", count: items.size - CHIP_CAP)) if items.size > CHIP_CAP
          end
          render Components::Icons::ChevronRight.new(css: "h-4 w-4 shrink-0 text-muted")
        end
      end

      #: (untyped label) -> untyped
      def name_chip(label)
        span(class: "inline-flex max-w-full items-center truncate rounded-full " \
                    "bg-surface-container-high px-2.5 py-1 text-label-caps uppercase " \
                    "text-on-surface-variant") { label }
      end

      #: (untyped media, untyped run) -> untyped
      def status_row(media, run)
        div(class: "flex items-center gap-3 rounded-xl border border-card-border bg-surface-container p-3") do
          thumb(media)
          div(class: "flex flex-1 flex-col gap-1") do
            state_badge(media, run)
            # An ingest failure (#545) shows its own caption; a recognition
            # failure keeps the detailed provider-aware one + retry.
            span(class: "text-body-sm text-muted") { I18n.t("captures.session.ingest_failed") } if media.ingest_failed?
            render Components::Ui::RecognitionErrorCaption.new(run:) if run&.failed?
            retry_button(media) if run&.failed?
          end
        end
      end

      #: (untyped media) -> untyped
      def thumb(media)
        div(class: "flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden " \
                   "rounded-lg bg-surface-container-high text-muted") do
          if media.image_displayable?
            img(
              src: MediaVariants::TransformUrl.for(media, :thumb),
              class: "h-full w-full object-cover", alt: "", loading: "lazy"
            )
          elsif media.image_unavailable?
            render Components::Icons::ImageOff.new(css: "h-6 w-6")
          else
            render Components::Icons::Camera.new(css: "h-6 w-6")
          end
        end
      end

      #: (untyped media, untyped run) -> untyped
      def state_badge(media, run)
        # Ingest state (#545) takes precedence: a pending media is still being
        # optimised (no image/run yet); a failed one never reached recognition.
        return render Components::Ui::RecognitionState.new(state: :processing) if media.pending?
        return render Components::Ui::RecognitionState.new(state: :failed) if media.ingest_failed?
        return span(class: "text-label-caps uppercase text-muted") { I18n.t("ui.states.queued") } if run.nil?

        render Components::Ui::RecognitionState.new(state: RUN_TO_STATE.fetch(run.status, :queued))
      end

      #: (untyped media) -> untyped
      def retry_button(media)
        button_to(
          I18n.t("ui.buttons.retry"),
          view_context.move_box_capture_retry_path(@box.move_id, @box, media_id: media.id),
          method: :post,
          class: "self-start rounded-full bg-error px-3 py-1 text-label-caps uppercase text-on-error"
        )
      end

      #: () -> untyped
      def empty_state
        p(class: "text-body-md text-muted") { I18n.t("captures.session.empty") }
      end
    end
  end
end

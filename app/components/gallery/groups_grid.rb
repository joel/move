# frozen_string_literal: true

module Components
  module Gallery
    # The Groups half of the gallery (#633): item-family cards, or whichever of
    # the three deliberate states applies. This component IS the Turbo Stream
    # replace unit — the BroadcastSubscriber re-renders it whole when a
    # recompute lands, so every state transition (organizing → ready, stale →
    # fresh) arrives live without a reload. It loads its own data through
    # Clusters::Overview unless the controller hands one in, keeping the page
    # render and the broadcast render byte-consistent. Read-only — no mutating
    # affordances, safe for every viewer.
    class GroupsGrid < Components::Base
      ID = "gallery-groups-grid"

      #: (move: untyped, ?overview: untyped) -> void
      def initialize(move:, overview: nil)
        @move = move
        @overview = overview || Clusters::Overview.new.call(move: move).value!
      end

      #: () -> void
      def view_template
        div(id: ID, class: "flex flex-col gap-section-gap") do
          case @overview.status
          when :no_items then no_items_state
          when :organizing then organizing_state
          when :none then none_state
          else
            cap_notice if @overview.capped
            grid
          end
        end
      end

      private

      #: () -> untyped
      def grid
        media = preview_media
        div(class: "grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3") do
          @overview.clusters.each do |cluster|
            render Components::Gallery::GroupCard.new(
              move: @move, cluster: cluster,
              previews: displayable_previews(cluster, media),
              box_numbers: @overview.box_numbers.fetch(cluster.id, [])
            )
          end
        end
      end

      # Resolve the preview photo ids Clusters::Overview returned into Media.
      # Media is packs/captures' public model; loading it here in the root
      # gallery layer keeps packs/search free of the cross-domain reference
      # (one query for every card's candidates). Preloads the Active Storage
      # attachment + blob — image_displayable? and TransformUrl touch both per
      # photo, so without it a full page (≤100 cards × candidates) or a
      # broadcast render would fan out to hundreds of queries (the gallery
      # grid's idiom).

      #: () -> Hash[untyped, untyped]
      def preview_media
        ids = @overview.preview_media_ids.values.flatten.uniq
        Media.where(id: ids).includes(image_attachment: :blob).index_by(&:id)
      end

      # A card's ≤PREVIEWS displayable photos, in the quilt order Overview
      # ranked them — dropping any that turned non-displayable since (bounded
      # staleness, self-heals next recompute).

      #: (untyped cluster, untyped media) -> Array[untyped]
      def displayable_previews(cluster, media)
        @overview.preview_media_ids.fetch(cluster.id, [])
                 .filter_map { |id| media[id] }
                 .select(&:image_displayable?)
                 .first(Components::Gallery::GroupCard::PREVIEWS)
      end

      #: () -> untyped
      def cap_notice
        p(class: "text-body-md text-on-surface-variant") do
          I18n.t("galleries.groups.capped", count: Clusters::Overview::CAP)
        end
      end

      #: () -> untyped
      def no_items_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("galleries.groups.no_items.title"),
          description: I18n.t("galleries.groups.no_items.description")
        )
      end

      # Pre-first-compute only: the controller has already requested a refresh,
      # so the stream replaces this with the real grid when the recompute lands
      # (~the debounce later). The pulse is the only motion — quiet, ambient.

      #: () -> untyped
      def organizing_state
        div(class: "flex flex-col items-center gap-3 rounded-card border border-card-border " \
                   "bg-card px-6 py-12 text-center") do
          div(class: "h-10 w-10 animate-pulse rounded-full bg-accent-sage/30")
          p(class: "text-title-md text-text-warm") { I18n.t("galleries.groups.organizing.title") }
          p(class: "max-w-md text-body-md text-on-surface-variant") do
            I18n.t("galleries.groups.organizing.description")
          end
        end
      end

      #: () -> untyped
      def none_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Sparkles,
          title: I18n.t("galleries.groups.none.title"),
          description: I18n.t("galleries.groups.none.description")
        )
      end
    end
  end
end

# frozen_string_literal: true

module Components
  module Boxes
    # D1 — the unified box-contents grid: ONE surface replacing the old split of a
    # photo gallery + a separate items list. Each captured photo is a single card
    # (Components::Boxes::PhotoCard — the image + the names recognised in it as
    # chips); each manually-added item with no photo is a placeholder card
    # (Components::Boxes::ItemCard). The Item model is the invisible backbone
    # (search/manifest/labels still read it) — it's just never shown as its own list.
    #
    # Photos lead (most-recent capture first), then standalone cards (most-recent
    # first).
    class ContentsGrid < Components::Base
      # Above-the-fold cards load eagerly — two mobile rows / one sm row; the
      # photos render before standalone items, so indexing the media loop is
      # sufficient (#673).
      EAGER_TILES = 4

      # @rbs move: untyped
      # @rbs box: untyped
      # @rbs media: untyped
      # @rbs items: untyped
      # @rbs reviewable_media_ids: untyped
      # @rbs recoverable_media_ids: untyped
      # @rbs unpacked_media_ids: untyped
      # @rbs editable: bool
      # @rbs pinnable: bool
      # @rbs pinned_item_ids: untyped
      # @rbs return: void
      def initialize(move:, box:, media:, items:, reviewable_media_ids: [],
                     recoverable_media_ids: [], unpacked_media_ids: [], editable: false,
                     pinnable: false, pinned_item_ids: Set.new)
        @move = move
        @box = box
        @media = media # recent_first, blobs preloaded
        @items = items # all in-box items (removed ride along while unpacking, #727)
        @reviewable_media_ids = reviewable_media_ids.to_set
        @recoverable_media_ids = recoverable_media_ids.to_set
        @unpacked_media_ids = unpacked_media_ids.to_set
        # In-place checklist mode (#727): checked states render for anyone
        # viewing an unpacking box; the toggles need an editable Move too.
        @unpacking = box.unpacking?
        @interactive = @unpacking && editable
        # Find-list pin mode (#747): a closed box's cards carry the per-item
        # pin toggle. Independent of `editable` — viewers may pin (personal
        # rows only), and mutually exclusive with @unpacking by the state
        # machine (closed ∌ unpacking).
        @pinnable = pinnable
        @pinned_item_ids = pinned_item_ids
        # In-box items grouped by their source photo (only this box's photos are
        # rendered as cards).
        @items_by_media = items.group_by(&:source_media_id)
        # Items NOT represented by one of this box's photos get their own card so
        # they never vanish: manual items (nil source) AND items moved in from
        # another box, which keep their foreign source_media_id (Codex).
        box_media_ids = media.to_set(&:id)
        @standalone_items = items.reject { |i| i.source_media_id && box_media_ids.include?(i.source_media_id) }
      end

      #: () -> void
      def view_template
        # `refocus` restores focus to the tapped toggle after its card is
        # re-streamed (#727) — button ids are stable across presence flips.
        section(class: "flex flex-col gap-stack-gap", data: { controller: "refocus" }) do
          render Components::Boxes::ContentsHeader.new(
            total: @items.size,
            unpacked: @unpacking ? @items.count(&:removed?) : nil
          )
          any_cards? ? grid : empty
        end
      end

      private

      #: () -> untyped
      def any_cards?
        @media.any? || @standalone_items.any?
      end

      #: () -> untyped
      def grid
        div(class: "grid grid-cols-2 gap-3 sm:grid-cols-3") do
          @media.each_with_index do |media, index|
            render Components::Boxes::PhotoCard.new(
              move: @move, box: @box, media: media,
              items: @items_by_media[media.id] || [],
              reviewable: @reviewable_media_ids.include?(media.id),
              recoverable: @recoverable_media_ids.include?(media.id),
              unpacked: @unpacked_media_ids.include?(media.id),
              eager: index < EAGER_TILES,
              unpacking: @unpacking, interactive: @interactive,
              pinnable: @pinnable, pinned_item_ids: @pinned_item_ids
            )
          end
          # Standalone items most-recent first (items arrive created-ascending).
          # The eager index CONTINUES across them: when the box has fewer than
          # EAGER_TILES photos, image-backed item cards fill the first visible
          # row and must not lazy-load the likely LCP (#673 Codex).
          @standalone_items.reverse_each.with_index(@media.size) do |item, index|
            render Components::Boxes::ItemCard.new(
              item: item, move: @move, image_ready: @move.image_generation_ready?,
              eager: index < EAGER_TILES, unpacking: @interactive,
              pinnable: @pinnable, pinned: @pinned_item_ids.include?(item.id)
            )
          end
        end
      end

      #: () -> untyped
      def empty
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Camera,
          title: I18n.t("boxes.contents.empty_title"),
          description: I18n.t("boxes.contents.empty_description")
        )
      end
    end
  end
end

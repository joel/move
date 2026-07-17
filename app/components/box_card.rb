# frozen_string_literal: true

module Components
  # A2 Boxes Home grid item. Reuses Ui::Card's micro-bar slot for the bottom
  # summary strip and Ui::ProgressBar for the packed indicator. Item counts and
  # recognition runs arrive in later phases (D5/D4); `recognition_state` is the
  # integration point — passed nil until D4 supplies runs.
  class BoxCard < Components::Base
    include Phlex::Rails::Helpers::ButtonTo

    #: (box: untyped, ?item_count: untyped, ?recognition_state: untyped, ?highlight: untyped, ?duplicatable: untyped) -> void
    def initialize(box:, item_count: 0, recognition_state: nil, highlight: false, duplicatable: false)
      @box = box
      @item_count = item_count
      @recognition_state = recognition_state
      @highlight = highlight
      @duplicatable = duplicatable
    end

    #: () -> void
    def view_template
      # button_to renders a <form>, which is invalid inside an <a> — so the
      # duplicate control is an absolutely-positioned sibling of the card link
      # (MoveCard's sibling rule, overlaid on the corner instead of stacked).
      div(class: "relative") do
        a(href: move_box_path(@box.move_id, @box), class: link_classes) do
          render Components::Ui::Card.new(interactive: true, micro_bar: micro_bar) do
            header_row
            title_block
          end
        end
        duplicate_control if duplicatable?
      end
    end

    private

    # `rounded-card` so the one-time highlight ring (a box-shadow) follows the
    # card's shape when this is the just-created box (#336).

    # `h-full` keeps the link stretched to the grid cell (as the pre-wrapper
    # root <a> was), so the click zone and highlight ring cover the whole cell
    # even when a neighbouring card in the row is taller.

    #: () -> String
    def link_classes
      base = "block h-full rounded-card"
      @highlight ? "#{base} box-added-highlight" : base
    end

    # The control only earns its place when there is a size to copy — a
    # dimensionless box would duplicate to a plain empty box (that's what
    # "Add box" is for) and the "same dimensions" copy would over-promise.

    #: () -> untyped
    def duplicatable?
      @duplicatable && !@box.missing_dimensions?
    end

    #: () -> untyped
    def header_row
      div(class: "flex items-start justify-between gap-3") do
        div(
          class: "flex h-12 w-12 items-center justify-center rounded-full " \
                 "bg-surface-container-high text-accent-sage"
        ) { render Components::Icons::Boxes.new(css: "h-6 w-6") }

        # `pr-9` clears the duplicate button overlaid on the card's top-right
        # corner (h-9 w-9 at right-3) so the number badge / fragile chip never
        # sit under it.
        div(class: ["flex flex-col items-end gap-1.5", ("pr-9" if duplicatable?)].compact.join(" ")) do
          if @recognition_state
            render Components::Ui::RecognitionState.new(state: @recognition_state)
          else
            span(class: badge_classes) { badge_label }
          end
          # Manual fragile mark (Phase A) — terracotta, the design system's Fragile
          # tint (DESIGN.md), matching the box header chip and the printed label.
          render Components::Ui::Chip.new(label: I18n.t("boxes.fragile_badge"), kind: :tag) if @box.fragile?
        end
      end
    end

    # A one-tap "next box of the same size" (#658). The POST lands back on the
    # index where the created box gets the toast + highlight treatment.

    #: () -> untyped
    def duplicate_control
      label = I18n.t("boxes.index.duplicate_box", number: padded_number)
      button_to(
        duplicate_move_box_path(@box.move_id, @box),
        method: :post,
        class: "absolute right-3 top-3 flex h-9 w-9 items-center justify-center " \
               "rounded-full text-muted transition hover:bg-surface-container-high " \
               "hover:text-text-warm",
        aria: { label: label },
        title: label
      ) { render Components::Icons::Duplicate.new(css: "h-5 w-5") }
    end

    #: () -> untyped
    def title_block
      div do
        h3(class: "mb-1 text-headline-md text-text-warm") { title }
        p(class: "text-body-md text-muted") { items_label }
      end
    end

    #: () -> untyped
    def items_label
      @item_count.zero? ? I18n.t("boxes.card.no_items") : I18n.t("boxes.card.items", count: @item_count)
    end

    # Bottom strip: status + items placeholder, the packed progress bar, and a
    # terracotta warning when dimensions are missing.

    #: () -> untyped
    def micro_bar
      box = @box
      lambda do |card|
        card.div(class: "flex justify-between text-label-caps uppercase text-muted") do
          card.span { status_label }
          card.span { items_label }
        end
        card.render Components::Ui::ProgressBar.new(value: box.packed? ? 100 : 0, max: 100)
        next unless box.missing_dimensions?

        card.div(class: "flex items-center gap-1.5 text-label-caps uppercase text-secondary") do
          card.render Components::Icons::Alert.new(css: "h-4 w-4")
          card.span { I18n.t("boxes.card.missing_dimensions") }
        end
      end
    end

    #: () -> untyped
    def title
      @box.room&.name.presence || I18n.t("boxes.card.no_room")
    end

    #: () -> untyped
    def badge_label
      I18n.t("boxes.card.badge", number: padded_number)
    end

    # The card's visible identity is the zero-padded badge ("Box 01"), so every
    # label naming the box (badge, duplicate control) uses the same padding.

    #: () -> String
    def padded_number
      # Kernel.format (not bare `format`, which is a Phlex element helper).
      Kernel.format("%02d", @box.number.to_i)
    end

    #: () -> String
    def badge_classes
      "rounded-full bg-surface-container-high px-3 py-1 text-label-caps uppercase text-muted"
    end

    #: () -> untyped
    def status_label
      I18n.t("boxes.status.#{@box.status}", default: @box.status.titleize)
    end
  end
end

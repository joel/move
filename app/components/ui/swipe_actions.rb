# frozen_string_literal: true

module Components
  module Ui
    # Swipe-to-reveal row actions (iOS-style sliding item). The content layer
    # slides horizontally over absolutely-positioned option layers: `leading:`
    # (revealed by swiping right) and `trailing:` (revealed by swiping left),
    # both proc slots rendered only when given (Ui::Card `micro_bar:` pattern).
    # The layers are `lg:hidden` — at lg+ callers show inline buttons instead
    # and the swipe-actions Stimulus controller no-ops (it gates on the
    # layers' computed visibility, so CSS owns the breakpoint). With no slots
    # the wrapper renders the same DOM shape without any swipe wiring.
    #
    # The caller's `id` stays on the outermost element so Turbo Stream
    # remove/replace targets keep working; caller `data[:controller]` /
    # `data[:action]` tokens are merged. The wrapper `css:` must include an
    # opaque background — the content layer occludes the option layers with
    # `bg-inherit`.
    #
    # Slot procs receive this component, but for Rails helpers (button_to,
    # form_with) use the calling component's own lexical scope — the helpers
    # come from the caller's includes, not from this class:
    #
    #   render Components::Ui::SwipeActions.new(
    #     id: dom_id, data: { controller: "inline-rename" },
    #     css: "rounded-card border border-card-border bg-card",
    #     content_css: "flex items-center gap-3 p-4",
    #     leading: ->(_c) { button(class: OPTION_CLASSES, ...) { ... } },
    #     trailing: ->(_c) { button_to(path, class: OPTION_CLASSES, ...) { ... } }
    #   ) { ...row content... }
    #
    # Option buttons follow one recipe: OPTION_CLASSES + a tint pair
    # (bg-accent-sage/15 text-accent-sage · bg-error text-on-error), an icon,
    # a short visible label-caps label, and the full accessible name on an
    # aria-label. An open row closes on tap-away, on a tap of its content, or
    # when focus moves on — and only one row is open per page.
    class SwipeActions < Components::Base
      # The shared shell for a slot's option button — tint, icon and label are
      # the caller's (see the recipe in DESIGN.md).
      OPTION_CLASSES = "flex w-full flex-col items-center justify-center gap-1"

      #: (?id: untyped, ?data: untyped, ?css: untyped, ?content_css: untyped, ?leading: untyped, ?trailing: untyped) -> void
      def initialize(id: nil, data: {}, css: nil, content_css: nil, leading: nil, trailing: nil)
        @id = id
        @data = data
        @css = css
        @content_css = content_css
        @leading = leading
        @trailing = trailing
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def view_template(&)
        div(id: @id, data: wrapper_data, class: wrapper_classes) do
          # Layers first, content last: the content paints on top without any
          # z-index, occluding the layers until the controller translates it.
          layer(:leading, @leading, "left-0") if @leading
          layer(:trailing, @trailing, "right-0") if @trailing
          content(&)
        end
      end

      private

      #: () -> bool
      def swipeable?
        !(@leading.nil? && @trailing.nil?)
      end

      #: (untyped name, untyped slot, untyped side) -> untyped
      def layer(name, slot, side)
        div(
          class: "absolute inset-y-0 #{side} flex w-24 lg:hidden",
          data: {
            swipe_actions_target: name.to_s,
            # Keyboard/AT path: tabbing into an occluded option button snaps
            # the row open so the focused control is visible (WCAG 2.4.7).
            action: "focusin->swipe-actions#open"
          }
        ) { slot.call(self) }
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def content(&)
        div(class: content_classes, data: content_data, &)
      end

      #: () -> String
      def content_classes
        # bg-inherit: the occluding surface is whatever opaque background the
        # caller put on the wrapper, so tinted rows stay one colour.
        structural = swipeable? ? "ha-swipe-content relative bg-inherit" : "relative"
        [structural, @content_css].compact.join(" ")
      end

      #: () -> untyped
      def content_data
        return {} unless swipeable?

        {
          swipe_actions_target: "content",
          action: "pointerdown->swipe-actions#start pointermove->swipe-actions#move " \
                  "pointerup->swipe-actions#end pointercancel->swipe-actions#cancel " \
                  "click->swipe-actions#guardClick:capture " \
                  "focusin->swipe-actions#closeFromContent"
        }
      end

      #: () -> untyped
      def wrapper_data
        return @data unless swipeable?

        data = @data.dup
        data[:controller] = [data[:controller], "swipe-actions"].compact.join(" ")
        data[:action] = [
          data[:action],
          # Turbo must never snapshot an open/translated row (lightbox idiom);
          # focus leaving the row closes it (keyboard counterpart of tap-away).
          "turbo:before-cache@document->swipe-actions#teardown",
          "focusout->swipe-actions#closeIfFocusLeft"
        ].compact.join(" ")
        data
      end

      #: () -> String
      def wrapper_classes
        ["relative overflow-hidden", @css].compact.join(" ")
      end
    end
  end
end

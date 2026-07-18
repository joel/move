# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::BlurUpImage (#681). The sample LQIP
  # is a committed 24px gradient JPEG (~900 chars of base64 — what a real
  # preview weighs); the src deliberately 404s so the blurred preview layer
  # stays visible for inspection instead of being covered by a loaded image.
  class BlurUpImagePreview < Lookbook::Preview
    # rubocop:disable Layout/LineLength -- a committed base64 sample can't wrap
    SAMPLE_LQIP = "/9j/2wBDABALDA4MChAODQ4SERATGCgaGBYWGDEjJR0oOjM9PDkzODdASFxOQERXRTc4UG1RV19iZ2hnPk1xeXBkeFxlZ2P/2wBDARESEhgVGC8aGi9jQjhCY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2NjY2P/wAARCAASABgDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwDj4rX2q5Fa+1XorX2q5Fa+1OMjOhiSjFa+1FbUVr7UV0KR7EMToQRAelXIgPSiiuSJ8pQLkQHpRRRW6PXhsf/Z"
    # rubocop:enable Layout/LineLength

    # What a first view paints instantly, before any network byte arrives.
    def blur_layer_only
      render Tile.new do
        render Components::Ui::BlurUpImage.new(
          src: "/missing-so-the-blur-stays-visible.jpg",
          lqip: SAMPLE_LQIP, img_class: "h-full w-full object-cover"
        )
      end
    end

    # No lqip (legacy/unanalyzed blob): just the img — the wrapper grey shows,
    # exactly the pre-#681 placeholder.
    def without_lqip
      render Tile.new do
        render Components::Ui::BlurUpImage.new(
          src: "/missing.jpg", img_class: "h-full w-full object-cover"
        )
      end
    end

    # Preview-only stand-in for the contract every caller upholds: a relative,
    # overflow-hidden tile (the gallery/contents/review tile shape).
    class Tile < Components::Base
      #: () ?{ () -> untyped } -> untyped
      def view_template(&)
        div(
          class: "relative flex aspect-square w-48 items-center justify-center " \
                 "overflow-hidden rounded-card bg-surface-container-high",
          &
        )
      end
    end
  end
end

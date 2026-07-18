# frozen_string_literal: true

module Components
  module Ui
    # Blur-up image (LQIP, #681): paints a tiny blurred inline preview under the
    # real image the instant the page renders; the image simply covers it as it
    # loads, so first views read as "sharpening" instead of a grey box popping
    # to a photo. Zero JS — no load listeners or transition machinery.
    #
    #   render Components::Ui::BlurUpImage.new(
    #     src: url, lqip: media.image_lqip, loading: "lazy", decoding: "async",
    #     img_class: "h-full w-full object-cover"
    #   )
    #
    # The caller's wrapper must be `relative overflow-hidden` (every image tile
    # and hero container already is): the preview layer is absolutely
    # positioned and slightly over-scaled so the blur never shows a hard edge.
    # Without an lqip (legacy/unanalyzed blob) only the img renders and the
    # wrapper's own background shows through — exactly today's placeholder.
    class BlurUpImage < Components::Base
      # The value is server-generated (ImageNormalizer), but gate on strict
      # base64 anyway so a corrupt/foreign metadata value can never reach the
      # style attribute.
      BASE64 = %r{\A[A-Za-z0-9+/]+={0,2}\z}

      #: (src: untyped, ?lqip: String?, ?alt: String, ?img_class: String, **untyped) -> void
      def initialize(src:, lqip: nil, alt: "", img_class: "", **img_attrs)
        @src = src
        @lqip = lqip
        @alt = alt
        @img_class = img_class
        @img_attrs = img_attrs
      end

      #: () -> untyped
      def view_template
        if @lqip.is_a?(String) && @lqip.match?(BASE64)
          div(
            class: "pointer-events-none absolute inset-0 bg-cover bg-center",
            style: "background-image: url(data:image/jpeg;base64,#{@lqip}); " \
                   "filter: blur(12px); transform: scale(1.1)",
            aria_hidden: "true"
          )
        end
        # `relative` lifts the img above the preview layer (later in DOM order).
        img(src: @src, alt: @alt, class: "relative #{@img_class}".strip, **@img_attrs)
      end
    end
  end
end

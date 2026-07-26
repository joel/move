# frozen_string_literal: true

module Views
  module Searches
    # D1 — Search. A centred search hero, semantic example-query hints (empty
    # state), and a results grid (item photo + match badge + box/room location).
    # Renders inside the AppLayout sidebar shell. Light from Refined-Palette
    # tokens (Stitch is dark canonical). Cards lead with the item's source photo
    # (a same-geometry placeholder tile when there is none); the design's
    # one-line description is omitted — items carry no description field
    # (see DESIGN-DISCREPANCIES §D1).
    class Index < Views::Base
      include Phlex::Rails::Helpers::FormWith

      # First grid row (lg is 3-col) loads eager, the rest lazy (#673).
      EAGER_THUMBS = 3

      #: (move: untyped, query: untyped, results: untyped, ?recent_searches: untyped) -> void
      def initialize(move:, query:, results:, recent_searches: [])
        @move = move
        @query = query.to_s
        @results = results
        @recent_searches = recent_searches
      end

      #: () -> void
      def view_template
        hero
        if @query.blank?
          hints
        elsif @results.any?
          results
        else
          no_results
        end
      end

      private

      #: () -> bool
      def searched? = @query.present?

      #: () -> untyped
      def hero
        div(class: "mx-auto flex w-full max-w-3xl flex-col items-center #{searched? ? "pt-2" : "pt-10"}") do
          search_form
        end
      end

      #: () -> untyped
      def search_form
        form_with(url: move_search_path(@move), method: :get, class: "w-full") do
          div(class: "flex items-center gap-3 rounded-card border border-card-border bg-card " \
                     "px-5 py-4 focus-within:border-accent-sage transition") do
            render Components::Icons::Search.new(css: "h-6 w-6 text-accent-sage")
            input(
              type: "search", name: "q", value: @query,
              placeholder: I18n.t("searches.placeholder"), autofocus: true,
              class: "w-full bg-transparent text-headline-md text-text-warm " \
                     "placeholder:text-muted focus:outline-none"
            )
          end
        end
      end

      # Empty state: once the user has run a successful search, surface their own
      # recent queries in place of the static examples (#338, ux principles 4 & 1).

      #: () -> untyped
      def hints
        @recent_searches.any? ? recent_searches : examples
      end

      #: () -> untyped
      def examples
        div(class: "mx-auto mt-8 flex max-w-3xl flex-col items-center gap-4") do
          hint_label(Components::Icons::Sparkles, I18n.t("searches.hint"))
          examples = I18n.t("searches.examples") #: untyped
          chip_row { examples.each { |example| example_chip(example) } }
        end
      end

      #: () -> untyped
      def recent_searches
        div(class: "mx-auto mt-8 flex max-w-3xl flex-col items-center gap-4") do
          hint_label(Components::Icons::Clock, I18n.t("searches.recent"))
          chip_row { @recent_searches.each { |query| example_chip(query) } }
        end
      end

      #: (untyped icon, untyped text) -> untyped
      def hint_label(icon, text)
        p(class: "flex items-center gap-2 text-body-md text-muted") do
          render icon.new(css: "h-4 w-4")
          plain text
        end
      end

      #: () ?{ (*untyped) -> untyped } -> untyped
      def chip_row(&)
        div(class: "flex flex-wrap justify-center gap-3", &)
      end

      #: (untyped text) -> untyped
      def example_chip(text)
        a(
          href: move_search_path(@move, q: text),
          class: "rounded-full border border-card-border bg-card px-5 py-2 text-body-md " \
                 "text-text-warm transition hover:border-accent-sage hover:bg-surface-container-high"
        ) { "“#{text}”" }
      end

      #: () -> untyped
      def results
        div(class: "mt-8 flex flex-col gap-6") do
          h2(class: "border-b border-card-border pb-4 text-headline-lg-mobile md:text-headline-xl text-text-warm") do
            I18n.t("searches.results_count", count: @results.size, query: @query)
          end
          div(class: "grid grid-cols-1 gap-stack-gap sm:grid-cols-2 lg:grid-cols-3") do
            @results.each_with_index { |result, index| result_card(result, eager: index < EAGER_THUMBS) }
          end
        end
      end

      #: (untyped result, eager: bool) -> untyped
      def result_card(result, eager:)
        a(
          href: move_item_path(@move, result.item),
          class: "group flex flex-col overflow-hidden rounded-card border border-card-border bg-card " \
                 "transition hover:-translate-y-0.5 hover:border-accent-sage"
        ) do
          thumbnail(result, eager:)
          div(class: "flex flex-1 flex-col gap-4 p-5") do
            h3(class: "text-headline-md text-text-warm transition-colors group-hover:text-accent-sage") do
              result.item.name
            end
            location(result)
          end
        end
      end

      # The photo fills a fixed-height area so photo and placeholder cards keep
      # identical geometry; the match badge overlays it on a blurred backing to
      # stay readable over any image.

      #: (untyped result, eager: bool) -> untyped
      def thumbnail(result, eager:)
        media = result.item.source_media
        div(class: "relative flex h-48 shrink-0 items-center justify-center overflow-hidden " \
                   "bg-surface-container-high text-muted") do
          thumbnail_visual(media, alt: result.item.name.to_s, eager:)
          div(class: "absolute right-3 top-3 rounded-full bg-card/90 shadow-sm backdrop-blur-sm") do
            match_badge(result.matched_on)
          end
        end
      end

      #: (untyped media, alt: String, eager: bool) -> untyped
      def thumbnail_visual(media, alt:, eager:)
        if media&.image_displayable?
          render Components::Ui::BlurUpImage.new(
            src: MediaVariants::TransformUrl.for(media, :thumb),
            lqip: media.image_lqip,
            alt: alt,
            loading: eager ? "eager" : "lazy",
            decoding: "async",
            img_class: "h-full w-full object-cover transition duration-300 group-hover:scale-105"
          )
        elsif media&.image_unavailable?
          render Components::Icons::ImageOff.new(css: "h-10 w-10")
        else
          render Components::Icons::Boxes.new(css: "h-10 w-10")
        end
      end

      #: (untyped matched_on) -> untyped
      def match_badge(matched_on)
        render Components::Ui::Chip.new(
          label: I18n.t("searches.match.#{matched_on}"),
          kind: matched_on == :exact ? :room : :category
        )
      end

      #: (untyped result) -> untyped
      def location(result)
        div(class: "mt-auto flex items-center gap-3 rounded-card border border-card-border bg-page p-3") do
          div(class: "flex h-8 w-8 items-center justify-center rounded-lg " \
                     "bg-accent-sage/15 text-accent-sage") do
            render Components::Icons::Boxes.new(css: "h-5 w-5")
          end
          div(class: "flex flex-col") do
            span(class: "text-label-caps uppercase text-muted") { I18n.t("searches.location") }
            span(class: "text-body-md text-text-warm") { location_label(result) }
          end
          render Components::Icons::ChevronRight.new(css: "ml-auto h-5 w-5 text-muted")
        end
      end

      #: (untyped result) -> String
      def location_label(result)
        box = I18n.t("searches.box", number: result.box_number)
        result.room_name.present? ? "#{box} · #{result.room_name}" : box
      end

      #: () -> untyped
      def no_results
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Search,
          title: I18n.t("searches.empty.title", query: @query),
          description: I18n.t("searches.empty.description")
        )
      end
    end
  end
end

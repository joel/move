# frozen_string_literal: true

module Views
  module StyleGuide
    # Living reference for the Move design system. Every primitive is shown in
    # light and dark so the page doubles as the Phase D0 verification surface.
    class Show < Views::Base
      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: "Phase D0",
            title: "Design system",
            subtitle: "Move — Mindful Moving. Every primitive, light + dark."
          )
          color_section
          typography_section
          buttons_section
          cards_section
          chips_section
          forms_section
          progress_section
          recognition_section
          feedback_section
          navigation_section
        end
      end

      private

      # Render the same content in a light and a dark panel, side by side.

      #: () ?{ (*untyped) -> untyped } -> untyped
      def theme_pair(&)
        div(class: "grid gap-4 sm:grid-cols-2") do
          theme_panel("Light", "light", &)
          theme_panel("Dark", "dark", &)
        end
      end

      #: (untyped label, untyped scope) ?{ (*untyped) -> untyped } -> untyped
      def theme_panel(label, scope, &)
        div(class: "#{scope} flex flex-col gap-4 rounded-card border border-card-border bg-page p-6") do
          p(class: "text-label-caps uppercase text-muted") { label }
          yield
        end
      end

      #: (untyped title) ?{ (*untyped) -> untyped } -> untyped
      def section(title, &)
        div(class: "flex flex-col gap-4") do
          h2(class: "text-headline-md text-text-warm") { title }
          yield
        end
      end

      # Constrain `position: fixed` descendants to a preview box (a transform on
      # the ancestor establishes a containing block for fixed positioning).
      #: (untyped height) ?{ (*untyped) -> untyped } -> untyped
      def preview_box(height, &)
        div(
          class: "relative #{height} overflow-hidden rounded-card border border-card-border",
          style: "transform: translateZ(0)", &
        )
      end

      #: () -> untyped
      def color_section
        section("Colour") do
          theme_pair do
            div(class: "grid grid-cols-2 gap-3 sm:grid-cols-4") do
              swatch("page", "bg-page text-text-warm border border-card-border")
              swatch("card", "bg-card text-text-warm border border-card-border")
              swatch("accent-sage", "bg-accent-sage text-page")
              swatch("text-warm", "bg-text-warm text-page")
              swatch("primary", "bg-primary text-on-primary")
              swatch("secondary", "bg-secondary text-on-secondary")
              swatch("tertiary", "bg-tertiary text-on-tertiary")
              swatch("error", "bg-error text-on-error")
              swatch("surface-container", "bg-surface-container text-on-surface")
              swatch("surface-…-high", "bg-surface-container-high text-on-surface")
              swatch("surface-…-highest", "bg-surface-container-highest text-on-surface")
              swatch("outline", "bg-outline text-page")
            end
          end
        end
      end

      #: (untyped name, untyped classes) -> untyped
      def swatch(name, classes)
        div(class: "flex h-16 items-end rounded-card p-2 text-label-caps uppercase #{classes}") do
          span { name }
        end
      end

      #: () -> untyped
      def typography_section
        section("Typography — Plus Jakarta Sans") do
          theme_pair do
            div(class: "flex flex-col gap-3") do
              p(class: "text-headline-xl text-text-warm") { "Headline XL" }
              p(class: "text-headline-lg text-text-warm") { "Headline LG" }
              p(class: "text-headline-md text-text-warm") { "Headline MD" }
              p(class: "text-body-lg text-on-surface-variant") { "Body large — calm and unhurried." }
              p(class: "text-body-md text-on-surface-variant") { "Body medium — the default reading size." }
              p(class: "text-label-caps uppercase text-muted") { "Label caps" }
            end
          end
        end
      end

      #: () -> untyped
      def buttons_section
        section("Buttons") do
          theme_pair do
            div(class: "flex flex-wrap items-center gap-3") do
              render Components::Ui::Button.new(label: "Primary")
              render Components::Ui::Button.new(label: "Secondary", variant: :secondary)
              render Components::Ui::Button.new(label: "Terracotta", variant: :terracotta)
              render Components::Ui::Button.new(label: "Ghost", variant: :ghost)
              render Components::Ui::Button.new(label: "Danger", variant: :danger)
              render Components::Ui::Button.new(label: "Disabled", disabled: true)
              render Components::Ui::Button.new(label: "New Box", icon: Components::Icons::Plus)
            end
            render Components::Ui::Button.new(label: "Full width", full_width: true)
          end
        end
      end

      #: () -> untyped
      def cards_section
        section("Cards") do
          theme_pair do
            render Components::Ui::Card.new do
              p(class: "text-label-caps uppercase text-muted") { "Box 01" }
              h3(class: "text-headline-md text-text-warm") { "Everyday Dishes" }
              p(class: "text-body-md text-on-surface-variant") { "Kitchen • Fragile" }
            end
            render Components::Ui::Card.new(
              interactive: true,
              micro_bar: lambda { |c|
                c.render Components::Ui::ProgressBar.new(value: 12, max: 12, label: "Packed")
              }
            ) do
              h3(class: "text-headline-md text-text-warm") { "With summary micro-bar" }
              p(class: "text-body-md text-on-surface-variant") { "Interactive — hover to lift." }
            end
          end
        end
      end

      #: () -> untyped
      def chips_section
        section("Chips") do
          theme_pair do
            div(class: "flex flex-wrap gap-3") do
              render Components::Ui::Chip.new(label: "Kitchen", kind: :room)
              render Components::Ui::Chip.new(label: "Fragile", kind: :tag)
              render Components::Ui::Chip.new(label: "Books", kind: :category)
              render Components::Ui::Chip.new(label: "Selected", selected: true)
            end
          end
        end
      end

      #: () -> untyped
      def forms_section
        section("Fields & selects") do
          theme_pair do
            render Components::Ui::Field.new(name: "box_name", label: "Box name", placeholder: "e.g. Everyday Dishes")
            render Components::Ui::Field.new(name: "bad", label: "With error", value: "oops", error: "Required field")
            render Components::Ui::Select.new(
              name: "unit", label: "Unit system",
              options: [%w[Metric metric], %w[Imperial imperial]], selected: "metric"
            )
          end
        end
      end

      #: () -> untyped
      def progress_section
        section("Progress") do
          theme_pair do
            render Components::Ui::ProgressBar.new(value: 12, max: 12, label: "Packed")
            render Components::Ui::ProgressBar.new(value: 24, max: 30, label: "Items", tone: :terracotta)
            render Components::Ui::ProgressBar.new(value: 3, max: 8, label: "Packing")
          end
        end
      end

      #: () -> untyped
      def recognition_section
        section("Recognition states") do
          theme_pair do
            div(class: "flex flex-wrap gap-3") do
              %i[queued processing succeeded needs_correction auto_confirmed pending_review].each do |state|
                render Components::Ui::RecognitionState.new(state: state)
              end
              render Components::Ui::RecognitionState.new(state: :failed, retry_href: "#")
            end
          end
        end
      end

      #: () -> untyped
      def feedback_section
        section("Toasts & empty states") do
          theme_pair do
            render Components::Ui::Toast.new(variant: :success, message: "Box saved.")
            render Components::Ui::Toast.new(variant: :error, message: "Something needs your attention.")
            render Components::Ui::Toast.new(variant: :info, message: "A gentle heads up.")
            render Components::Ui::EmptyState.new(title: "No boxes yet", description: "Start a box to see it here.") do
              render Components::Ui::Button.new(label: "New Box", icon: Components::Icons::Plus)
            end
          end
        end
      end

      #: () -> untyped
      def navigation_section
        section("Navigation chrome") do
          p(class: "text-body-md text-on-surface-variant") do
            "Sidebar (lg+) and bottom tab bar (mobile). Active = sage pill. " \
              "Scan/Menu point at stubs until D9/D13."
          end
          preview_box("h-[420px]") do
            render Components::Ui::Sidebar.new(active: :boxes)
            render Components::Ui::BottomTabBar.new(active: :boxes)
          end
        end
      end
    end
  end
end

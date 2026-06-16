# frozen_string_literal: true

module Views
  module Activities
    # G1 — Activity Feed Wall. A calm, append-only timeline of everything that has
    # happened in a Move, newest first, grouped by day. Each row names the actor
    # and what they did (i18n via ActivityPresenter); deleted rows can be restored
    # and the latest edit of a record can be reverted. Built against the Stitch
    # "Activity - Populated (Mobile Dark)" screen using Phase D0 tokens.
    class Index < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:, groups:, restorable:, revertable:, next_before: nil, next_before_id: nil)
        @move = move
        @groups = groups
        @restorable = restorable
        @revertable = revertable
        @next_before = next_before
        @next_before_id = next_before_id
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: I18n.t("activities.index.eyebrow"),
            title: I18n.t("activities.index.title")
          )
          @groups.empty? ? empty_state : feed
        end
      end

      private

      def empty_state
        render Components::Ui::EmptyState.new(
          icon: Components::Icons::Clock,
          title: I18n.t("activities.index.empty_title"),
          description: I18n.t("activities.index.empty_body")
        ) do
          a(
            href: move_boxes_path(@move),
            class: "rounded-full bg-primary px-6 py-3 text-body-md font-bold " \
                   "text-on-primary transition hover:bg-primary/90"
          ) { I18n.t("activities.index.empty_cta") }
        end
      end

      def feed
        div(class: "flex flex-col gap-section-gap") do
          @groups.each { |date, presenters| day_group(date, presenters) }
          load_older if @next_before
        end
      end

      def day_group(date, presenters)
        section(class: "relative flex flex-col gap-5") do
          # Faint connector line behind the avatars.
          div(class: "absolute left-5 top-8 bottom-2 w-px bg-outline-variant/60", aria_hidden: "true")
          h2(class: "text-label-caps uppercase text-on-surface-variant") { day_label(date) }
          presenters.each { |presenter| row(presenter) }
        end
      end

      def row(presenter)
        div(class: "relative flex items-start gap-4") do
          avatar(presenter)
          div(class: "flex flex-1 items-start justify-between gap-4 pt-0.5") do
            div(class: "flex flex-col gap-1") do
              summary(presenter)
              meta(presenter)
            end
            trailing(presenter)
          end
        end
      end

      def avatar(presenter)
        tint = if presenter.accent?
                 "bg-secondary-container text-on-secondary-container"
               else
                 "bg-primary-container text-on-primary-container"
               end
        div(
          class: "relative z-10 flex h-10 w-10 shrink-0 items-center justify-center " \
                 "rounded-full text-sm font-bold #{tint}"
        ) { presenter.initials }
      end

      def summary(presenter)
        tone = presenter.accent? ? "text-secondary" : "text-on-surface"
        p(class: "text-body-md #{tone}") do
          strong(class: "font-bold text-on-surface") { presenter.actor_label }
          whitespace
          plain presenter.predicate
        end
      end

      def meta(presenter)
        div(class: "flex items-center gap-2") do
          span(class: "text-xs text-on-surface-variant") do
            I18n.t("activities.relative_time", time: helpers.time_ago_in_words(presenter.occurred_at))
          end
          span(
            class: "rounded-full bg-surface-container px-2 py-0.5 text-[10px] font-bold " \
                   "uppercase tracking-tight text-on-surface-variant"
          ) { presenter.source_label }
        end
      end

      def trailing(presenter)
        id = presenter.activity.id
        if @restorable.include?(id)
          restore_button(id)
        elsif @revertable.include?(id)
          revert_button(id)
        end
      end

      def restore_button(id)
        button_to(
          I18n.t("activities.restore.action"), move_activity_restore_path(@move, id),
          method: :post,
          class: "shrink-0 rounded-full bg-primary px-4 py-2 text-xs font-bold " \
                 "text-on-primary transition hover:bg-primary/90 active:scale-95"
        )
      end

      def revert_button(id)
        button_to(
          I18n.t("activities.revert.action"), move_activity_revert_path(@move, id),
          method: :post,
          class: "shrink-0 text-xs font-bold text-primary underline underline-offset-4 " \
                 "decoration-primary/30 transition hover:text-primary-fixed active:opacity-60"
        )
      end

      def load_older
        div(class: "flex justify-center pt-2") do
          a(
            # iso8601(6): occurred_at is timestamp(6); whole-second precision would
            # move the cursor off the real boundary and skip rows again (#194).
            href: move_activity_path(@move, before: @next_before.iso8601(6), before_id: @next_before_id),
            class: "text-body-md font-semibold text-on-surface-variant transition hover:text-text-warm"
          ) { I18n.t("activities.index.load_older") }
        end
      end

      def day_label(date)
        today = Date.current
        return I18n.t("activities.day.today") if date == today
        return I18n.t("activities.day.yesterday") if date == today - 1

        I18n.l(date, format: :long)
      end
    end
  end
end

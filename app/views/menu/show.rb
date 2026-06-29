# frozen_string_literal: true

module Views
  module Menu
    # F3 — Menu hub. The top-level controls hub for a Move: grouped rows linking
    # to the Organize surfaces (vocabularies, members, summary) and the App
    # surfaces (settings, assistant, account), plus switch-move and sign-out.
    # Built against the Stitch "Menu Hub - Mobile View" screen, rendered from
    # project tokens. Admin-only destinations (Members) are omitted for
    # non-admins so the hub never offers a dead-end 403.
    class Show < Views::Base
      include Phlex::Rails::Helpers::ButtonTo
      include Phlex::Rails::Helpers::Routes

      def initialize(move:, admin:, editor:)
        @move = move
        @admin = admin
        @editor = editor
      end

      def view_template
        div(class: "flex flex-col gap-section-gap") do
          render Components::Ui::SectionHeader.new(
            eyebrow: @move.name,
            title: I18n.t("menu.show.title"),
            subtitle: I18n.t("menu.show.subtitle")
          )
          group(I18n.t("menu.show.organize"), organize_links)
          group(I18n.t("menu.show.app"), app_links)
          actions
        end
      end

      private

      def organize_links
        links = [
          [I18n.t("menu.show.gallery"), Components::Icons::Camera, move_gallery_path(@move)],
          [I18n.t("menu.show.activity"), Components::Icons::Clock, move_activity_path(@move)],
          [I18n.t("menu.show.rooms"), Components::Icons::Boxes,
           move_vocabularies_path(@move, "rooms")]
        ]
        links << [I18n.t("menu.show.members"), Components::Icons::Users, move_members_path(@move)] if @admin
        links << [I18n.t("menu.show.summary"), Components::Icons::Chart, move_summary_path(@move)]
        links << [I18n.t("menu.show.box_steps"), Components::Icons::Bolt, move_box_steps_path(@move)] if @editor
        links << [I18n.t("menu.show.label_print"), Components::Icons::Tag, move_label_print_path(@move)]
        links
      end

      def app_links
        [
          [I18n.t("menu.show.settings"), Components::Icons::Settings, move_settings_path(@move)],
          [I18n.t("menu.show.assistant"), Components::Icons::Sparkles, "#{move_settings_path(@move)}#assistant"],
          [I18n.t("menu.show.account"), Components::Icons::UserCircle, view_context.account_path]
        ]
      end

      def group(title, links)
        section(aria_label: title, class: "flex flex-col gap-stack-gap") do
          h2(class: "text-label-caps uppercase text-muted") { title }
          div(class: "flex flex-col gap-3") { links.each { |label, icon, href| row(label, icon, href) } }
        end
      end

      def row(label, icon, href)
        a(
          href: href,
          class: "flex items-center gap-4 rounded-card border border-card-border bg-card p-4 " \
                 "transition hover:bg-surface-container-high"
        ) do
          div(
            class: "flex h-10 w-10 shrink-0 items-center justify-center rounded-full " \
                   "bg-surface-container-high text-accent-sage"
          ) { render icon.new(css: "h-5 w-5") }
          span(class: "flex-1 text-headline-md text-text-warm") { label }
          render Components::Icons::ChevronRight.new(css: "h-5 w-5 text-on-surface-variant")
        end
      end

      def actions
        section(aria_label: I18n.t("menu.show.actions"), class: "flex flex-col gap-3") do
          a(
            href: moves_path,
            class: "flex items-center justify-center gap-3 rounded-full border border-card-border " \
                   "bg-card px-6 py-3 text-body-md font-semibold text-text-warm transition " \
                   "hover:bg-surface-container-high"
          ) do
            render Components::Icons::Swap.new(css: "h-5 w-5")
            span { I18n.t("menu.show.switch_move") }
          end
          button_to(
            I18n.t("menu.show.sign_out"), view_context.rodauth.logout_path,
            method: :post,
            class: "rounded-full px-6 py-3 text-body-md font-semibold text-on-surface-variant " \
                   "transition hover:text-error"
          )
        end
      end
    end
  end
end

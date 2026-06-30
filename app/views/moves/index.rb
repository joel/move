# frozen_string_literal: true

module Views
  module Moves
    # A1 — Select Move (list view) / empty state.
    class Index < Views::Base
      def initialize(moves:, organization: nil)
        @moves = moves
        @organization = organization
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-8") do
          header
          render Components::Moves::Collection.new(moves: @moves, organization: @organization)
        end
      end

      private

      def header
        div(class: "flex flex-col gap-4 md:flex-row md:items-end md:justify-between") do
          div do
            h1(class: "text-headline-lg text-text-warm") { I18n.t("moves.index.title") }
            p(class: "mt-2 text-body-md text-on-surface-variant") { I18n.t("moves.index.subtitle") }
          end
          render Components::Ui::Button.new(
            label: I18n.t("moves.index.create"),
            href: view_context.new_move_path,
            full_width: false
          )
        end
      end
    end
  end
end

# frozen_string_literal: true

module Views
  module Moves
    # A1 — Select Move (list view) / empty state.
    class Index < Views::Base
      def initialize(moves:)
        @moves = moves
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-3xl flex-col gap-8 px-4 py-8") do
          header
          @moves.any? ? list : empty_state
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

      def list
        section(class: "flex flex-col gap-4") do
          @moves.each { |move| render Components::MoveCard.new(move: move) }
        end
      end

      def empty_state
        render Components::Ui::EmptyState.new(
          title: I18n.t("moves.empty.title"),
          description: I18n.t("moves.empty.description")
        ) do
          render Components::Ui::Button.new(
            label: I18n.t("moves.empty.create"),
            href: view_context.new_move_path
          )
        end
      end
    end
  end
end

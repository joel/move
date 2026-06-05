# frozen_string_literal: true

module Views
  module Moves
    # A1 — Create New Move (form view).
    class New < Views::Base
      include Phlex::Rails::Helpers::LinkTo

      def initialize(move:)
        @move = move
      end

      def view_template
        div(class: "mx-auto flex w-full max-w-2xl flex-col gap-8 px-4 py-8") do
          header
          div(class: "rounded-card border border-card-border bg-card p-6") do
            render Components::MoveForm.new(move: @move)
          end
          link_to(I18n.t("moves.new.back"), view_context.moves_path,
                  class: "ha-button ha-button-secondary self-start")
        end
      end

      private

      def header
        div do
          h1(class: "text-headline-lg text-text-warm") { I18n.t("moves.new.title") }
          p(class: "mt-2 text-body-md text-on-surface-variant") { I18n.t("moves.new.subtitle") }
        end
      end
    end
  end
end

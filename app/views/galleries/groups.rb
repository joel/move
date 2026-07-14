# frozen_string_literal: true

module Views
  module Galleries
    # Gallery, Groups half (#633): the Move's item families — related things
    # scattered across boxes — as spread-first cards. Same header as the photo
    # half; the room filter and sort are deliberately absent (families span
    # rooms — either control would be zero-value chrome here). The grid mounts
    # a Turbo Stream so a finished recompute replaces it live.
    class Groups < Views::Base
      include Phlex::Rails::Helpers::TurboStreamFrom

      #: (move: untyped, overview: untyped) -> void
      def initialize(move:, overview:)
        @move = move
        @overview = overview
      end

      #: () -> void
      def view_template
        div(class: "flex flex-col gap-section-gap") do
          header
          render Components::Gallery::ViewToggle.new(move: @move, active: "groups")
          turbo_stream_from(@move, :gallery_groups)
          render Components::Gallery::GroupsGrid.new(move: @move, overview: @overview)
        end
      end

      private

      #: () -> untyped
      def header
        render Components::Ui::SectionHeader.new(
          eyebrow: @move.name,
          title: I18n.t("galleries.groups.title"),
          subtitle: I18n.t("galleries.groups.subtitle")
        )
      end
    end
  end
end

# frozen_string_literal: true

module Components
  module Ui
    # The five primary destinations shared by the bottom tab bar (mobile) and
    # the sidebar (desktop) — Design Spec §3. With a Move in context every
    # destination is a Move-scoped route; with no Move they fall back to stubs
    # (D0). The Menu slot opens the F3 hub (D13), available to any member.
    module NavDestinations
      Destination = Data.define(:key, :label_key, :icon, :href, :elevated)

      STUB_HREF = "#"

      # Move-aware destinations: Boxes (D2), Search (D8), Summary (D12), and Menu
      # (D13) link to the active Move when one is in context (Current.move); Scan
      # resolves too. With no Move, all are stubs (D0).
      def self.for_move(move = Current.move)
        h = Rails.application.routes.url_helpers
        [
          Destination.new(:boxes, "ui.nav.boxes", Components::Icons::Boxes,
                          move ? h.move_boxes_path(move) : STUB_HREF, false),
          Destination.new(:search, "ui.nav.search", Components::Icons::Search,
                          move ? h.move_search_path(move) : STUB_HREF, false),
          Destination.new(:scan, "ui.nav.scan", Components::Icons::Camera,
                          move ? h.move_scan_path(move) : STUB_HREF, true),
          Destination.new(:summary, "ui.nav.summary", Components::Icons::Chart,
                          move ? h.move_summary_path(move) : STUB_HREF, false),
          Destination.new(:menu, "ui.nav.menu", Components::Icons::Menu,
                          move ? h.move_menu_path(move) : STUB_HREF, false)
        ]
      end

      # Backwards-compatible stateless default (no Move context).
      def self.default
        for_move(nil)
      end

      # Whether the current user may mutate the active Move's contents — drives
      # whether chrome-level create affordances (the sidebar "New Box") are shown.
      # A UI affordance read off Current (the server still enforces the boundary):
      # an editing role (admin/contributor) on a writable Move. Hidden for viewers,
      # archived Moves, and when there is no Move in context.
      def self.editor?(move = Current.move)
        return false if move.nil? || Current.user.nil?

        move.writable? && (move.membership_for(Current.user)&.can_edit? || false)
      end
    end
  end
end

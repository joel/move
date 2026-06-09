# frozen_string_literal: true

module Components
  module Ui
    # The five primary destinations shared by the bottom tab bar (mobile) and
    # the sidebar (desktop) — Design Spec §3. Scan and Menu target screens whose
    # routes land in later phases (E2 in D9, F3 in D13); until then their `href`
    # is a stub. D1 swaps these stubs for Move-scoped routes.
    module NavDestinations
      Destination = Data.define(:key, :label_key, :icon, :href, :elevated)

      STUB_HREF = "#"

      # Move-aware destinations: Boxes (D2) and Search (D8) link to the active
      # Move when one is in context (Current.move); Scan/Summary stay stubs until
      # their phases (D9/D12). Menu routes admins to F1 Members & Roles (D11);
      # for non-admins it stays a stub until the D13 settings hub replaces it.
      # With no Move, all are stubs (D0).
      def self.for_move(move = Current.move)
        h = Rails.application.routes.url_helpers
        [
          Destination.new(:boxes, "ui.nav.boxes", Components::Icons::Boxes,
                          move ? h.move_boxes_path(move) : STUB_HREF, false),
          Destination.new(:search, "ui.nav.search", Components::Icons::Search,
                          move ? h.move_search_path(move) : STUB_HREF, false),
          Destination.new(:scan, "ui.nav.scan", Components::Icons::Camera,
                          move ? h.move_scan_path(move) : STUB_HREF, true),
          Destination.new(:summary, "ui.nav.summary", Components::Icons::Chart, STUB_HREF, false),
          Destination.new(:menu, "ui.nav.menu", Components::Icons::Menu, menu_href(move, h), false)
        ]
      end

      # F1 Members is admin-only, so only surface the link for an admin of the
      # current Move; everyone else keeps the stub (no dead-end 403 from the nav).
      def self.menu_href(move, helpers)
        return STUB_HREF if move.nil? || Current.user.nil?
        return STUB_HREF unless move.membership_for(Current.user)&.admin?

        helpers.move_members_path(move)
      end

      # Backwards-compatible stateless default (no Move context).
      def self.default
        for_move(nil)
      end
    end
  end
end

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

      def self.default
        [
          Destination.new(:boxes, "ui.nav.boxes", Components::Icons::Boxes, STUB_HREF, false),
          Destination.new(:search, "ui.nav.search", Components::Icons::Search, STUB_HREF, false),
          Destination.new(:scan, "ui.nav.scan", Components::Icons::Camera, STUB_HREF, true),
          Destination.new(:summary, "ui.nav.summary", Components::Icons::Chart, STUB_HREF, false),
          Destination.new(:menu, "ui.nav.menu", Components::Icons::Menu, STUB_HREF, false)
        ]
      end
    end
  end
end

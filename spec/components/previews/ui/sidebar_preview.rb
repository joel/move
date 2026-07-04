# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::Sidebar (#530). Hidden below the lg
  # breakpoint — widen the preview viewport to see it. Rendered outside a Move,
  # so destinations are the stateless stubs and the editor-only "New Box"
  # action stays hidden (Current is empty in a preview request).
  class SidebarPreview < Lookbook::Preview
    def default
      render Components::Ui::Sidebar.new
    end

    def search_active
      render Components::Ui::Sidebar.new(active: :search)
    end
  end
end

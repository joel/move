# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::CompactSelect (#696) — the label-less
  # pill select of the members roster and the box-detail jump-to-box.
  class CompactSelectPreview < Lookbook::Preview
    ROLES = [%w[Admin admin], %w[Editor editor], %w[Viewer viewer]].freeze

    def default
      render Components::Ui::CompactSelect.new(name: "member[role]", aria_label: "Change role", options: ROLES)
    end

    def with_selected
      render Components::Ui::CompactSelect.new(
        name: "member[role]", aria_label: "Change role", options: ROLES, selected: "viewer"
      )
    end

    # The jump-to-box shape: padded labels, with the "1"/"01" tie kept raw.
    def box_jump
      render Components::Ui::CompactSelect.new(
        name: "id", aria_label: "Jump to box", selected: "b",
        options: [["Box 1", "a"], ["Box 01", "b"], ["Box 002", "c"]]
      )
    end

    # Adds the change->auto-submit#submit action; the ENCLOSING form must carry
    # data-controller="auto-submit" (rendered without one here, so it is inert).
    def auto_submit
      render Components::Ui::CompactSelect.new(
        name: "member[role]", aria_label: "Change role", options: ROLES, selected: "editor", auto_submit: true
      )
    end
  end
end

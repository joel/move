# frozen_string_literal: true

module Components
  module Vocabularies
    # How each managed vocabulary kind looks: the Ui::Chip tint of its row
    # medallion and the icon shown in the medallion and the empty state.
    #
    # This is a presentation mapping, so it lives with the components that
    # render it, not on Vocabulary (packs/vocabularies/app/public), which stays
    # a data contract with no reference to the UI layer (#472). Every
    # Vocabulary::KINDS entry needs a style here; an unknown kind raises
    # KeyError rather than rendering unstyled.
    module Presentation
      STYLES = {
        "rooms" => { chip_kind: :room, icon: Components::Icons::Boxes }
      }.freeze #: Hash[String, { chip_kind: Symbol, icon: untyped }]

      # The Ui::Chip::KINDS key that tints the row medallion.

      #: (untyped vocabulary) -> Symbol
      def self.chip_kind(vocabulary)
        STYLES.fetch(vocabulary.kind)[:chip_kind]
      end

      # The icon component class (call .new(css:) to render it).

      #: (untyped vocabulary) -> untyped
      def self.icon(vocabulary)
        STYLES.fetch(vocabulary.kind)[:icon]
      end
    end
  end
end

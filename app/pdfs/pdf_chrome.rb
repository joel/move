# frozen_string_literal: true

# Shared drawing chrome for the app's Prawn documents (#702 extracted the
# banner after its third copy): the tinted notice band (confidential warnings,
# privacy notes) and the origin→destination route line. Complements PdfFonts.
#
# ⚠ The band uses `text_box`, which silently IGNORES a `color:` option (#508) —
# the text color comes from `fill_color`, set around the box here. Keep copy
# short enough for the fixed band height; a height that no longer fits its text
# clips silently (Prawn draws what fits).
module PdfChrome
  # Draws a full-width tinted band with small text and restores fill color.
  # `background`/`foreground` are hex strings; `height` in pt must accommodate the wrapped text.
  def banner(doc, text, background:, foreground:, height:)
    doc.bounding_box([0, doc.cursor], width: doc.bounds.width) do
      doc.fill_color background
      doc.fill_rectangle([0, doc.cursor], doc.bounds.width, height)
      doc.fill_color foreground
      doc.text_box text, at: [10, doc.cursor - 8], width: doc.bounds.width - 20, size: 9
      doc.fill_color "000000"
    end
    doc.move_down height + 12
  end

  # "Origin  →  Destination", or nil when neither address is set.
  def route_line(move)
    [move.origin_address, move.destination_address].compact_blank.join("  →  ").presence
  end
end

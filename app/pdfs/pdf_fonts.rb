# frozen_string_literal: true

# Registers a Unicode-capable TTF (Noto Sans, OFL) as the default font for a
# Prawn document. Prawn's built-in AFM fonts (Helvetica et al.) only encode
# Windows-1252, so rendering user-supplied names with accents, non-Latin scripts,
# emoji, or smart punctuation raises Prawn::Errors::IncompatibleStringEncoding —
# a 500 on Print label/manifest (#85). A TTF accepts any UTF-8 string; glyphs the
# font lacks (e.g. CJK, emoji) degrade to blank boxes instead of crashing.
#
# ⚠ Prawn colored-text gotcha (#508): plain `doc.text_box` silently IGNORES a
# `color:` option — the text inherits the ambient fill color, worst case invisible
# ink on a same-color background (the FRAGILE band bug). Only `doc.text(..., color:)`
# and formatted fragments (`formatted_text_box([{ text:, color: }])`) honor color.
# Never pass `color:` to `text_box`.
module PdfFonts
  FONT_DIR = Rails.root.join("app/assets/fonts")
  FAMILY = "NotoSans"

  def register_unicode_font(doc)
    doc.font_families.update(
      FAMILY => {
        normal: FONT_DIR.join("NotoSans-Regular.ttf").to_s,
        bold: FONT_DIR.join("NotoSans-Bold.ttf").to_s
      }
    )
    doc.font(FAMILY)
  end
end

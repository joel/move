# frozen_string_literal: true

require "prawn"

# #702 — the movers-facing insurance declaration: every transported item once,
# grouped by theme (the recognition `family` facet; nil-family items collect in
# a final "Miscellaneous" section), names aggregated with quantities. This
# document is SANITIZED BY DESIGN: it must never contain box numbers, room
# names, or photographs — its whole purpose is proving what is transported
# without revealing where any of it is packed. The privacy invariant is
# spec-enforced (spec/pdfs/insurance_declaration_pdf_spec.rb). The caller
# authorizes and emits the audit event (InsuranceDeclarations::Generate);
# this object only renders.
class InsuranceDeclarationPdf
  include PdfFonts
  include PdfChrome

  NOTE = "This declaration lists the goods in this move, grouped by category. " \
         "It intentionally contains no box numbers, room names, or photographs."
  EMPTY = "No items recorded yet."
  # The nil-family bucket's printed heading — PDF copy lives in the renderer.
  MISCELLANEOUS = "Miscellaneous"
  # Minimum space to start a section: heading + column header + one row — a
  # heading must never be orphaned at a page bottom.
  SECTION_MIN_CURSOR = 70
  # Manual row layout (NOT prawn-table): ~5x faster at scale because
  # prawn-table's per-cell measuring dominates (#708). Names WRAP to their
  # full (Ruby-truncated) length via doc.text in a bounded column — a
  # fixed-height text_box would silently clip long names at rendered width,
  # losing content the old table preserved (#709 review). ROW_MIN guards the
  # page break for the tallest possible row (3 wrapped lines + gap).
  ROW_MIN = 48
  ROW_GAP = 4
  QTY_WIDTH = 60
  NAME_MAX = 150

  # sections: [{ family: String | nil, lines: [[name, count], ...] }, ...] —
  # ordered, the nil (Miscellaneous) bucket last (InsuranceDeclarations::Generate).
  def initialize(move:, sections:, total_items:)
    @move = move
    @sections = sections
    @total_items = total_items
  end

  def render
    doc = Prawn::Document.new(page_size: "A4", margin: 40)
    register_unicode_font(doc)
    title(doc)
    meta(doc)
    note(doc)
    if @sections.empty?
      doc.text EMPTY, size: 10, color: "6B6B6B"
    else
      @sections.each { |section| section(doc, section) }
    end
    doc.render
  end

  private

  def title(doc)
    doc.text title_line("Insurance Declaration", @move), size: 22, style: :bold
    doc.move_down 4
  end

  def meta(doc)
    route = route_line(@move)
    doc.text route, size: 10, color: "6B6B6B" if route
    parts = []
    parts << "Move date: #{@move.planned_on.strftime("%-d %B %Y")}" if @move.planned_on
    parts << "Generated: #{Time.current.strftime("%-d %B %Y")}"
    parts << "#{@total_items} items in #{@sections.size} categories"
    doc.text parts.join("   ·   "), size: 10, color: "6B6B6B"
    doc.move_down 12
  end

  # Neutral info band (calmer tint than the confidential warnings): the privacy
  # intent is documented on the artifact itself, so a mover reading the
  # declaration knows the omission of locations is deliberate, not sloppy.

  def note(doc)
    banner(doc, NOTE, background: "EEF1E6", foreground: "5A6B4F", height: 38)
  end

  def section(doc, section)
    doc.start_new_page if doc.cursor < SECTION_MIN_CURSOR
    doc.text (section[:family] || MISCELLANEOUS).upcase_first, size: 13, style: :bold
    doc.move_down 6
    column_header(doc)
    section[:lines].each { |name, count| line_row(doc, name, count) }
    doc.move_down 16
  end

  def column_header(doc)
    y = doc.cursor
    doc.text_box "Item", at: [0, y], width: doc.bounds.width - QTY_WIDTH - 10, height: 14,
                         size: 9, style: :bold
    doc.text_box "Qty", at: [doc.bounds.width - QTY_WIDTH, y], width: QTY_WIDTH, height: 14,
                        size: 9, style: :bold, align: :right
    doc.move_down 14
    doc.stroke_color "CCCCCC"
    doc.stroke_horizontal_rule
    doc.stroke_color "000000"
    doc.move_down 4
  end

  def line_row(doc, name, count)
    if doc.cursor < ROW_MIN
      doc.start_new_page
      column_header(doc)
    end
    y = doc.cursor
    doc.text_box count.to_s, at: [doc.bounds.width - QTY_WIDTH, y], width: QTY_WIDTH, height: 14,
                             size: 9, align: :right
    doc.bounding_box([0, y], width: doc.bounds.width - QTY_WIDTH - 10) do
      doc.text name.truncate(NAME_MAX), size: 9
    end
    doc.move_down ROW_GAP
  end
end

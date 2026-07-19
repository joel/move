# frozen_string_literal: true

require "prawn"
require "prawn/table"

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
  # Minimum space to start a section: heading + table header + one row — a
  # heading must never be orphaned at a page bottom.
  SECTION_MIN_CURSOR = 70

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
    doc.text "Insurance Declaration — #{@move.name}", size: 22, style: :bold
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
    rows = [%w[Item Qty]] + section[:lines].map { |name, count| [name, count.to_s] }
    doc.table(rows, header: true, width: doc.bounds.width,
                    cell_style: { size: 9, padding: [6, 8] }) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = "F2F2F2"
      t.columns(1).align = :right
      t.columns(1).width = 60
    end
    doc.move_down 16
  end
end

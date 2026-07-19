# frozen_string_literal: true

require "prawn"
require "prawn/table"

# E1 — the authenticated A4 manifest for a Box: the detailed contents listing.
# Unlike the exterior label this DOES reveal contents, so it opens with a
# sensitive-content warning and must never be publicly shared (Domain §12.3). The
# caller is responsible for authorizing the read and emitting the audit event
# (see Manifests::Generate); this object only renders.
class BoxManifestPdf
  include PdfFonts
  include PdfChrome

  WARNING = "Confidential — this manifest lists the box contents. " \
            "Keep it with the move; do not share publicly or attach it to the exterior label."

  def initialize(box:, items:)
    @box = box
    @items = items
  end

  def render
    doc = Prawn::Document.new(page_size: "A4", margin: 40)
    register_unicode_font(doc)
    title(doc)
    meta(doc)
    warning(doc)
    table(doc)
    doc.render
  end

  private

  def title(doc)
    doc.text "Box ##{format("%03d", @box.number.to_i)} — Manifest", size: 22, style: :bold
    doc.move_down 4
  end

  def meta(doc)
    room = @box.room&.name.presence || "Unassigned"
    doc.text "Room: #{room}   ·   Status: #{@box.status.humanize}   ·   #{@items.size} items",
             size: 10, color: "6B6B6B"
    doc.move_down 12
  end

  def warning(doc)
    banner(doc, WARNING, background: "FBE9E7", foreground: "B23C17", height: 38)
  end

  def table(doc)
    rows = [%w[Item]] + @items.map { |item| [item.name] }

    doc.table(rows, header: true, width: doc.bounds.width,
                    cell_style: { size: 9, padding: [6, 8] }) do |t|
      t.row(0).font_style = :bold
      t.row(0).background_color = "F2F2F2"
    end
  end
end

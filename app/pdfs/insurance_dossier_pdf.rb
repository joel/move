# frozen_string_literal: true

require "prawn"
require "stringio"

# #702 — the private insurance claim dossier: every in_box item under its box's
# heading, each row carrying a photo thumbnail (the item's capture or generated
# image; a drawn placeholder when none). The inverse of the declaration: this
# document DOES reveal which box holds each item, so it opens with a red
# warning banner and is admin-only + audit-evented at the caller. `thumbnails`
# is a duck-typed collaborator responding to `fetch(media) -> bytes | nil`
# (InsuranceDossierRuns::ThumbnailCache) so this root class never references a
# pack constant. `render` yields (done, total) after each box section for the
# job's progress broadcasts (the BoxLabelsPdf pattern).
class InsuranceDossierPdf
  include PdfFonts
  include PdfChrome

  WARNING = "Private — this dossier shows which box holds each item, with photographs. " \
            "Do not give it to the moving company; share it only with your insurer " \
            "in the event of a claim."
  THUMB = 56
  ROW_HEIGHT = 64
  # Long names truncate EXPLICITLY (String#truncate's ellipsis) — Prawn's
  # shrink_to_fit shrinks to an illegible 5pt and then cuts silently (#508), the
  # worst behavior for a claim-evidence document. Room names truncate too: the
  # page-budget estimate assumes single-line box headings, and Room validates
  # only presence (#706 review round 4).
  NAME_MAX = 140
  ROOM_MAX = 60
  # Heading + at least the first item row must fit together.
  SECTION_MIN_CURSOR = ROW_HEIGHT + 40

  # sections: [{ box:, items: [Item, ...] }, ...] in box-number order.
  def initialize(move:, sections:, thumbnails:)
    @move = move
    @sections = sections
    @thumbnails = thumbnails
  end

  def render
    doc = Prawn::Document.new(page_size: "A4", margin: 40)
    register_unicode_font(doc)
    cover(doc)
    @sections.each_with_index do |section, index|
      box_section(doc, section)
      yield(index + 1, @sections.size) if block_given?
    end
    doc.render
  end

  private

  def cover(doc)
    doc.text "Insurance Claim Dossier — #{@move.name}", size: 22, style: :bold
    doc.move_down 4
    route = route_line(@move)
    doc.text route, size: 10, color: "6B6B6B" if route
    total_items = @sections.sum { |section| section[:items].size }
    doc.text "Generated: #{Time.current.strftime("%-d %B %Y")}   ·   " \
             "#{@sections.size} boxes · #{total_items} items",
             size: 10, color: "6B6B6B"
    doc.move_down 12
    banner(doc, WARNING, background: "FBE9E7", foreground: "B23C17", height: 44)
  end

  def box_section(doc, section)
    doc.start_new_page if doc.cursor < SECTION_MIN_CURSOR
    box = section[:box]
    room = (box.room&.name.presence || "Unassigned").truncate(ROOM_MAX)
    doc.text "Box ##{format("%03d", box.number.to_i)} — #{room}", size: 13, style: :bold
    doc.text "#{section[:items].size} items", size: 9, color: "6B6B6B"
    doc.move_down 8
    section[:items].each { |item| item_row(doc, item) }
    doc.move_down 12
  end

  def item_row(doc, item)
    doc.start_new_page if doc.cursor < ROW_HEIGHT
    top = doc.cursor
    thumbnail(doc, @thumbnails.fetch(item.source_media), top)
    # Two full lines at 10pt (NotoSans leading ≈ 13.6pt — a 24pt box only fits
    # ONE line and Prawn would cut before the Ruby marker): NAME_MAX chars wrap
    # within two lines, so the "..." from String#truncate always prints.
    doc.text_box item.name.truncate(NAME_MAX), at: [THUMB + 12, top - ((ROW_HEIGHT - 28) / 2)],
                                               width: doc.bounds.width - THUMB - 12, height: 28,
                                               size: 10, overflow: :truncate
    doc.move_cursor_to(top - ROW_HEIGHT + 6)
    doc.stroke_color "E2E2E2"
    doc.stroke_horizontal_rule
    doc.stroke_color "000000"
    doc.move_down 6
  end

  # One corrupt or unsupported blob must degrade to the placeholder, never fail
  # a 500-item run — hence the narrow rescue (the cache already nils missing/
  # unreadable masters; this catches bytes Prawn itself rejects).

  def thumbnail(doc, bytes, top)
    if bytes
      doc.image(StringIO.new(bytes), fit: [THUMB, THUMB], at: [0, top])
    else
      placeholder(doc, top)
    end
  rescue Prawn::Errors::UnsupportedImageType
    placeholder(doc, top)
  end

  def placeholder(doc, top)
    doc.fill_color "EFEFEF"
    doc.fill_rectangle([0, top], THUMB, THUMB)
    doc.fill_color "9A9A9A"
    doc.text_box "No photo", at: [0, top - ((THUMB - 8) / 2)], width: THUMB, height: 10,
                             size: 7, align: :center
    doc.fill_color "000000"
  end
end

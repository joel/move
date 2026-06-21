# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

# E1 — batch exterior labels: one PDF holding the per-box label (62×90mm portrait,
# Brother QL-820NWB on DK-22205 62mm continuous tape, #255) for many boxes in print
# order. Same layout as a single label — a full-tape-width QR hero that resolves
# (in-app, authenticated) to the box, with the box number, destination room, and the
# human-readable manual-entry token stacked beneath — repeated PAGE_COUNT (lid +
# side) pages per box. Carries **no contents** (Domain §12).
#
# `entries` is an ordered list of `{ box:, scan_url: }`. Each box's scan URL is built
# by the caller from the request host, so this builder stays pure and host-agnostic.
# `BoxLabelPdf` delegates here with a single entry, so the single-box endpoint and
# this batch share one tested layout.
class BoxLabelsPdf
  include PdfFonts
  include Prawn::Measurements # mm2pt() -> PDF points

  # Brother QL-820NWB on DK-22205 62mm **continuous** tape (#255): 62mm fixed tape
  # width, free cut length → 62×90mm portrait. MARGIN keeps content off the edges.
  LABEL_WIDTH_MM = 62
  LABEL_LENGTH_MM = 90
  MARGIN = 6 # ≈2mm — keeps content off the tape edges
  GAP = 8 # vertical gap between the QR and the text region
  NUMBER_SIZE = 28
  NUMBER_MIN_SIZE = 16
  ROOM_SIZE = 16 # destination room name; shrinks toward ROOM_MIN_SIZE if long
  ROOM_MIN_SIZE = 8
  TOKEN_SIZE = 9 # human-readable manual-entry fallback; shrinks to fit
  TOKEN_MIN_SIZE = 6

  # Two identical labels (pages) per box so the user can stick one on the lid and
  # one on a side in a single print job.
  PAGE_COUNT = 2

  # entries: [{ box:, scan_url: }, ...] in print order.
  def initialize(entries:)
    @entries = entries
  end

  # Returns the rendered PDF as a binary string (PAGE_COUNT pages per entry).
  # If a block is given it is yielded `(done, total)` after each box's pages are
  # laid out, so a caller (LabelPrintRuns::GenerateJob, #303) can report live
  # generation progress. The single-box BoxLabelPdf calls this without a block.
  def render
    doc = Prawn::Document.new(
      page_size: [mm2pt(LABEL_WIDTH_MM), mm2pt(LABEL_LENGTH_MM)], margin: MARGIN
    )
    register_unicode_font(doc)

    # Prawn::Document already opens the first page; every subsequent label page is
    # an explicit start_new_page.
    first = true
    total = @entries.size
    @entries.each_with_index do |entry, index|
      PAGE_COUNT.times do
        doc.start_new_page unless first
        first = false
        label_content(doc, entry[:box], entry[:scan_url])
      end
      yield(index + 1, total) if block_given?
    end

    doc.render
  end

  private

  def label_content(doc, box, scan_url)
    qr_bottom = qr(doc, scan_url)
    details(doc, box, top: qr_bottom - GAP)
  end

  # The hero QR: a square sized to the full printable WIDTH (the limiting dimension
  # in portrait), at the top. border_modules: 4 keeps the standard quiet zone; the
  # source PNG is rendered well above the printed size so the ~56mm code stays crisp.
  # Returns the y of the QR's bottom edge so the text stacks below.
  def qr(doc, scan_url)
    png = RQRCode::QRCode.new(scan_url).as_png(size: 660, border_modules: 4)
    side = doc.bounds.width
    doc.image StringIO.new(png.to_blob), width: side, height: side, at: [0, doc.bounds.top]
    doc.bounds.top - side
  end

  # Text region below the QR, stacked top→bottom and centered: box number
  # (prominent), destination room, then the small manual-entry token. Each is a
  # shrink-to-fit box bounded to its slice of the remaining height, so a big number /
  # long room name / long token scales down instead of overflowing the page (one
  # label per page — #162 / #255). +top+ is the region's top y.
  def details(doc, box, top:)
    number_height = top * 0.40
    room_height = top * 0.38
    fit_text(doc, "##{format("%03d", box.number.to_i)}",
             top: top, height: number_height, size: NUMBER_SIZE, min_size: NUMBER_MIN_SIZE)
    fit_text(doc, box.room&.name.presence || "Unassigned",
             top: top - number_height, height: room_height, size: ROOM_SIZE, min_size: ROOM_MIN_SIZE)
    fit_text(doc, box.qr_token,
             top: top - number_height - room_height, height: top * 0.22,
             size: TOKEN_SIZE, min_size: TOKEN_MIN_SIZE, color: "8A8A8A")
  end

  # Centered bold text scaled to fit a fixed slice of the page. +top+ is the y of the
  # slice's top edge (bounds-relative); +height+ is its height.
  def fit_text(doc, text, top:, height:, size:, min_size:, color: "1A1A1A")
    doc.text_box(
      text, at: [0, top], width: doc.bounds.width, height: height, align: :center,
            size: size, style: :bold, color: color,
            overflow: :shrink_to_fit, min_font_size: min_size
    )
  end
end

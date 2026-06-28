# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

# E1 — batch exterior labels: one PDF holding the per-box label (62×90mm portrait,
# Brother QL-820NWB on DK-22205 62mm continuous tape, #255) for many boxes in print
# order. Same layout as a single label — a full-tape-width QR hero that resolves
# (in-app, authenticated) to the box, with the box number, destination room, and the
# human-readable manual-entry token stacked beneath — repeated `copies` (default 2:
# lid + side) pages per box. Carries **no contents** (Domain §12).
#
# `copies` is the Move's `labels_per_box` setting (Phase 45), passed in by the caller
# so this builder stays Move-agnostic; it defaults to DEFAULT_COPIES (2) so a bare
# call (and pre-Phase-45 behaviour) is unchanged.
#
# `entries` is an ordered list of `{ box:, scan_url: }`. Each box's scan URL is built
# by the caller from the request host, so this builder stays pure and host-agnostic.
# `BoxLabelPdf` delegates here with a single entry, so the single-box endpoint and
# this batch share one tested layout.
#
# A box marked **fragile** (Phase A) prints a red FRAGILE band above the box number.
# This is a deliberate, single-purpose exception to the "labels carry no contents"
# rule (Domain §12): it's a handling instruction for movers, not an inventory of
# what's inside.
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
  FRAGILE_SIZE = 20 # the red FRAGILE handling band (fragile boxes only); shrinks to fit
  FRAGILE_MIN_SIZE = 10
  FRAGILE_COLOR = "C0392B" # warning red — matches the box header/card fragile chip

  # Default copies per box (lid + side) — the prior fixed count. Used when no
  # Move-configured `labels_per_box` is passed (a bare builder call, or a bulk job
  # enqueued before Phase 45 deployed), so behaviour is unchanged by default.
  DEFAULT_COPIES = 2

  # entries: [{ box:, scan_url: }, ...] in print order. copies: the Move's
  # labels_per_box (1..10) — how many identical pages to emit per box.
  def initialize(entries:, copies: DEFAULT_COPIES)
    @entries = entries
    @copies = copies
  end

  # Returns the rendered PDF as a binary string (`copies` pages per entry).
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
      @copies.times do
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
    top = fragile_band(doc, top) if box.fragile?
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

  # The red FRAGILE handling band, drawn at the top of the text region for a fragile
  # box (Phase A). A filled rounded rect with white centered text, occupying ~22% of
  # the region; returns the y of the region top BELOW it (band + a small gap) so the
  # number/room/token stack underneath. The only "contents" a label ever carries —
  # a handling instruction, not an inventory (see header).
  def fragile_band(doc, top)
    height = top * 0.22
    doc.fill_color FRAGILE_COLOR
    doc.fill_rounded_rectangle([0, top], doc.bounds.width, height, 4)
    doc.text_box(
      "FRAGILE", at: [0, top], width: doc.bounds.width, height: height,
                 align: :center, valign: :center, size: FRAGILE_SIZE, style: :bold,
                 color: "FFFFFF", overflow: :shrink_to_fit, min_font_size: FRAGILE_MIN_SIZE
    )
    doc.fill_color "000000"
    top - height - GAP
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

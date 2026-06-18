# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

# E1 — the opaque exterior label for a Box (66×80mm thermal roll, #253): box
# number, destination room, and
# the QR that resolves (in-app, authenticated) to the box. It carries **no
# contents** — that is the whole point of the exterior label (Domain §12). The
# scan URL is injected by the caller (built from the current request host) so the
# builder stays pure and host-agnostic.
class BoxLabelPdf
  include PdfFonts
  include Prawn::Measurements # mm2pt() -> PDF points

  BRAND = "MOVE"

  # Sized for the thermal label roll (#253): 67mm-wide die-cut stickers, 80mm long.
  # The width is held ~1mm under the roll so the printer doesn't reject a page that
  # exactly equals the media width ("Wrong Roll Type"); the height matches the
  # die-cut length. Replaces the old A7 (74×105mm) page, which was too wide for the
  # roll. MARGIN/QR_SIDE/NUMBER_SIZE are tuned so one label still fits a single page
  # at this smaller size (A7 had ~70pt more vertical room — see PAGE_COUNT / #162).
  LABEL_WIDTH_MM = 66
  LABEL_HEIGHT_MM = 80
  MARGIN = 12
  QR_SIDE = 90 # ~32mm — keeps border_modules:4 quiet zone scannable
  NUMBER_SIZE = 24
  ROOM_SIZE = 13 # destination room name; shrinks toward ROOM_MIN_SIZE if long
  ROOM_MIN_SIZE = 7

  def initialize(box:, scan_url:)
    @box = box
    @scan_url = scan_url
  end

  # Two identical pages so the user can print a pair of labels per box (e.g. one
  # for the lid and one for a side) in a single job.
  PAGE_COUNT = 2

  # Returns the rendered PDF as a binary string.
  def render
    doc = Prawn::Document.new(
      page_size: [mm2pt(LABEL_WIDTH_MM), mm2pt(LABEL_HEIGHT_MM)], margin: MARGIN
    )
    register_unicode_font(doc)

    PAGE_COUNT.times do |i|
      doc.start_new_page if i.positive?
      label_content(doc)
    end

    doc.render
  end

  private

  def label_content(doc)
    header(doc)
    number(doc)
    qr(doc)
    code(doc)
    room(doc)
  end

  def header(doc)
    doc.text BRAND, size: 8, character_spacing: 2, color: "8A8A8A"
    doc.move_down 2
  end

  def number(doc)
    doc.text "##{format("%03d", @box.number.to_i)}", size: NUMBER_SIZE, style: :bold, color: "1A1A1A"
    doc.move_down 4
  end

  def qr(doc)
    # border_modules: 4 keeps the standard QR quiet zone so scanners lock on
    # reliably; anything smaller risks unreadable labels on real paper.
    png = RQRCode::QRCode.new(@scan_url).as_png(size: 360, border_modules: 4)
    # QR_SIDE (~32mm) keeps the code comfortably scannable while leaving enough
    # vertical room for a (possibly two-line) destination room so a single label
    # never overflows onto a second page — the embedded Unicode TTF has taller line
    # metrics than Prawn's built-in fonts, and the 80mm roll (#253) has ~70pt less
    # room than the old A7 page (which is why this shrank from 120pt — see #162).
    doc.image StringIO.new(png.to_blob), width: QR_SIDE, height: QR_SIDE, position: :center
    doc.move_down 4
  end

  # Human-readable token under the QR so the scanner's camera-unavailable
  # fallback ("enter the code printed under the QR") is actually usable.
  def code(doc)
    doc.text @box.qr_token, size: 7, style: :bold, color: "8A8A8A",
                            align: :center, character_spacing: 0.5
    doc.move_down 6
  end

  # Room name is user-controlled vocabulary (any length), so render it into the
  # remaining space as a shrink-to-fit text box rather than flowing text: a long
  # name scales down (to ROOM_MIN_SIZE) instead of wrapping onto a second page,
  # which would break the one-label-per-page invariant (PAGE_COUNT / #162) and the
  # physical die-cut alignment (#253).
  def room(doc)
    doc.text "DESTINATION ROOM", size: 7, character_spacing: 1.5, color: "8A8A8A"
    doc.move_down 2
    name = @box.room&.name.presence || "Unassigned"
    doc.text_box(
      name, at: [0, doc.cursor], width: doc.bounds.width, height: doc.cursor,
            size: ROOM_SIZE, style: :bold, color: "1A1A1A",
            overflow: :shrink_to_fit, min_font_size: ROOM_MIN_SIZE
    )
  end
end

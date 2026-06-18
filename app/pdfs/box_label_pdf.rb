# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

# E1 — the opaque exterior label for a Box (62×29mm Brother QL die-cut, DK-11209,
# #255): the QR that resolves (in-app, authenticated) to the box, beside its box
# number and destination room. It carries **no contents** — that is the whole
# point of the exterior label (Domain §12). The scan URL is injected by the caller
# (built from the current request host) so the builder stays pure and host-agnostic.
#
# The label is tiny (62×29mm ≈ 176×82pt), so the layout is a two-column landscape:
# a height-filling QR on the left, and box number + destination room + the
# human-readable token stacked on the right. The token stays small but MUST remain
# (the scan page's camera-unavailable fallback tells users to "enter the code
# printed under the QR" — scans.en.yml `camera_unavailable`). The "MOVE" brand line
# is dropped — no room at 29mm, and the QR carries the identity.
class BoxLabelPdf
  include PdfFonts
  include Prawn::Measurements # mm2pt() -> PDF points

  # Brother QL DK-11209 die-cut media (#255). The printer rejects a job whose page
  # size doesn't match the loaded roll with "Wrong Roll Type", so the page is the
  # media size exactly; MARGIN keeps content inside the die-cut's ~1.5mm
  # unprintable border. (Replaces the #253 66×80mm page, which still mismatched
  # this roll.) The driver's selected media must ALSO be DK-11209 or the printer
  # errors regardless of page size.
  LABEL_WIDTH_MM = 62
  LABEL_HEIGHT_MM = 29
  MARGIN = 6 # ≈2mm — keeps content inside the DK-11209 unprintable border
  GUTTER = 8 # gap between the QR and the text column
  NUMBER_SIZE = 20
  NUMBER_MIN_SIZE = 11
  ROOM_SIZE = 11 # destination room name; shrinks toward ROOM_MIN_SIZE if long
  ROOM_MIN_SIZE = 6
  TOKEN_SIZE = 7 # human-readable manual-entry fallback; shrinks to fit one line
  TOKEN_MIN_SIZE = 5

  def initialize(box:, scan_url:)
    @box = box
    @scan_url = scan_url
  end

  # Two identical labels (pages) per box so the user can stick one on the lid and
  # one on a side in a single print job.
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
    side = qr(doc)
    details(doc, left: side + GUTTER)
  end

  # Square QR on the left, sized to the full label height (the limiting dimension)
  # so it stays as scannable as the small die-cut allows. border_modules: 4 keeps
  # the standard quiet zone — anything smaller risks unreadable labels on real
  # paper. Returns the side length so the text column knows where to start.
  def qr(doc)
    png = RQRCode::QRCode.new(@scan_url).as_png(size: 360, border_modules: 4)
    side = doc.bounds.height
    doc.image StringIO.new(png.to_blob), width: side, height: side, at: [0, doc.bounds.top]
    side
  end

  # Right column, stacked top→bottom: box number (prominent), destination room, and
  # the small manual-entry token. Each is a shrink-to-fit box bounded to its slice
  # of the column height, so a big number / long room name / long token scales down
  # instead of wrapping or overflowing the one-per-page die-cut (#162 / #255).
  def details(doc, left:)
    width = doc.bounds.width - left
    doc.bounding_box([left, doc.bounds.top], width: width, height: doc.bounds.height) do
      h = doc.bounds.height
      fit_text(doc, "##{format("%03d", @box.number.to_i)}",
               top: h, height: h * 0.42, size: NUMBER_SIZE, min_size: NUMBER_MIN_SIZE)
      fit_text(doc, @box.room&.name.presence || "Unassigned",
               top: h * 0.58, height: h * 0.32, size: ROOM_SIZE, min_size: ROOM_MIN_SIZE)
      fit_text(doc, @box.qr_token,
               top: h * 0.26, height: h * 0.26, size: TOKEN_SIZE, min_size: TOKEN_MIN_SIZE,
               color: "8A8A8A")
    end
  end

  # Bold text scaled to fit a fixed slice of the current bounding box. +top+ is the
  # y of the slice's top edge (bbox-relative); +height+ is its height.
  def fit_text(doc, text, top:, height:, size:, min_size:, color: "1A1A1A")
    doc.text_box(
      text, at: [0, top], width: doc.bounds.width, height: height,
            size: size, style: :bold, color: color,
            overflow: :shrink_to_fit, min_font_size: min_size
    )
  end
end

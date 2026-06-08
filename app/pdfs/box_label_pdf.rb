# frozen_string_literal: true

require "rqrcode"
require "chunky_png"

# E1 — the opaque A7 exterior label for a Box: box number, destination room, and
# the QR that resolves (in-app, authenticated) to the box. It carries **no
# contents** — that is the whole point of the exterior label (Domain §12). The
# scan URL is injected by the caller (built from the current request host) so the
# builder stays pure and host-agnostic.
class BoxLabelPdf
  BRAND = "MOVE"

  def initialize(box:, scan_url:)
    @box = box
    @scan_url = scan_url
  end

  # Returns the rendered PDF as a binary string.
  def render
    doc = Prawn::Document.new(page_size: "A7", margin: 18)
    doc.font_families.update("Helvetica" => { normal: "Helvetica", bold: "Helvetica-Bold" })

    header(doc)
    number(doc)
    qr(doc)
    code(doc)
    room(doc)

    doc.render
  end

  private

  def header(doc)
    doc.text BRAND, size: 8, character_spacing: 2, color: "8A8A8A"
    doc.move_down 2
  end

  def number(doc)
    doc.text "##{format("%03d", @box.number.to_i)}", size: 34, style: :bold, color: "1A1A1A"
    doc.move_down 6
  end

  def qr(doc)
    # border_modules: 4 keeps the standard QR quiet zone so scanners lock on
    # reliably; anything smaller risks unreadable labels on real paper.
    png = RQRCode::QRCode.new(@scan_url).as_png(size: 360, border_modules: 4)
    side = 150
    doc.image StringIO.new(png.to_blob), width: side, height: side, position: :center
    doc.move_down 6
  end

  # Human-readable token under the QR so the scanner's camera-unavailable
  # fallback ("enter the code printed under the QR") is actually usable.
  def code(doc)
    doc.text @box.qr_token, size: 7, style: :bold, color: "8A8A8A",
                            align: :center, character_spacing: 0.5
    doc.move_down 8
  end

  def room(doc)
    doc.text "DESTINATION ROOM", size: 7, character_spacing: 1.5, color: "8A8A8A"
    doc.text(@box.room&.name.presence || "Unassigned", size: 14, style: :bold, color: "1A1A1A")
  end
end

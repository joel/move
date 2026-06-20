# frozen_string_literal: true

# E1 — the opaque exterior label for a single Box (62×90mm portrait, Brother
# QL-820NWB on DK-22205 62mm continuous tape, #255): a full-tape-width QR that
# resolves (in-app, authenticated) to the box, with the box number, destination
# room, and the human-readable token stacked beneath it. It carries **no contents**
# (Domain §12). The scan URL is injected by the caller (built from the current
# request host) so the builder stays pure and host-agnostic.
#
# The layout lives in BoxLabelsPdf (the batch builder); this is the single-box entry
# point — it delegates with one entry so single and batch share one tested layout.
class BoxLabelPdf
  def initialize(box:, scan_url:)
    @box = box
    @scan_url = scan_url
  end

  # Returns the rendered PDF as a binary string (two identical pages — lid + side).
  def render
    BoxLabelsPdf.new(entries: [{ box: @box, scan_url: @scan_url }]).render
  end
end

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
  # copies: the Move's labels_per_box (Phase 45); defaults to the prior fixed count
  # so a bare call still renders 2 (lid + side).
  def initialize(box:, scan_url:, copies: BoxLabelsPdf::DEFAULT_COPIES)
    @box = box
    @scan_url = scan_url
    @copies = copies
  end

  # Returns the rendered PDF as a binary string (`copies` identical pages).
  def render
    BoxLabelsPdf.new(entries: [{ box: @box, scan_url: @scan_url }], copies: @copies).render
  end
end

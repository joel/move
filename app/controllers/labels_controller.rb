# frozen_string_literal: true

# E1 — serves the opaque exterior label (62×90mm portrait, Brother QL continuous
# tape) as an inline PDF. The QR encodes the
# tenant-scoped resolve URL (scan_resolve_url) built from the current request
# host, so it points at this org's subdomain. Carries no contents.
class LabelsController < MoveScopedController
  before_action :set_box

  # GET /moves/:move_id/boxes/:box_id/label
  def show
    authorize! @box, to: :label?, with: BoxPolicy
    pdf = BoxLabelPdf.new(
      box: @box, scan_url: move_scan_resolve_url(@move, @box.qr_token), copies: @move.labels_per_box
    )
    send_data pdf.render, filename: filename, type: "application/pdf", disposition: "inline"
  end

  private

  def set_box
    @box = authorized_scope(@move.boxes.includes(:room)).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def filename
    "box-#{format("%03d", @box.number.to_i)}-label.pdf"
  end
end

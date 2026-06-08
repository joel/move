# frozen_string_literal: true

# E1 — serves the authenticated A4 manifest as an inline PDF. Manifests::Generate
# assembles the contents and records the sensitive read (manifest.viewed audit);
# this controller authorizes, then streams the rendered PDF.
class ManifestsController < MoveScopedController
  before_action :set_box

  # GET /moves/:move_id/boxes/:box_id/manifest
  def show
    authorize! @box, to: :manifest?, with: BoxPolicy
    box, items = Manifests::Generate.new.call(box: @box, actor: current_user).value!.values_at(:box, :items)
    pdf = BoxManifestPdf.new(box:, items:)
    send_data pdf.render, filename: filename, type: "application/pdf", disposition: "inline"
  end

  private

  def set_box
    @box = authorized_scope(@move.boxes.includes(:room)).find(params.expect(:box_id))
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def filename
    "box-#{format("%03d", @box.number.to_i)}-manifest.pdf"
  end
end

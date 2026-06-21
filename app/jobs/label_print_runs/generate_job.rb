# frozen_string_literal: true

require "stringio"

module LabelPrintRuns
  # Renders a bulk label-print PDF in the background, reporting live progress (#303).
  # Restores the Apartment tenant (jobs never inherit the request tenant), builds
  # BoxLabelsPdf box-by-box — reporting each box via LabelPrintRuns::RecordProgress
  # (throttled to ~20 broadcasts) — then attaches the finished PDF to the run and
  # finalizes it. The QR scan URLs are built from the request `host`/`protocol`
  # passed in at enqueue, since a job has no request of its own.
  class GenerateJob < ApplicationJob
    queue_as :default

    def perform(run_id, tenant:, host:, protocol:)
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        run = LabelPrintRun.find_by(id: run_id)
        return unless run&.in_progress? # gone, or a retry after it already finished/failed

        generate(run, host, protocol)
      end
    end

    private

    def generate(run, host, protocol)
      entries = run.move.boxes.in_number_range(run.from_number, run.to_number).includes(:room).map do |box|
        { box: box, scan_url: scan_url(run.move, box, host, protocol) }
      end
      step = [run.total_count / 20, 1].max
      pdf = BoxLabelsPdf.new(entries: entries).render do |done, total|
        RecordProgress.new.call(run_id: run.id, completed: done) if (done % step).zero? || done == total
      end
      run.document.attach(io: StringIO.new(pdf), filename: filename(run), content_type: "application/pdf")
      run.update!(status: "completed", completed_count: run.total_count, finished_at: Time.current)
      Broadcasting.broadcast_status(run)
    rescue StandardError # rubocop:disable Move/BroadRescue -- mark failed + broadcast, then re-raise (no swallow)
      run.update!(status: "failed", finished_at: Time.current)
      Broadcasting.broadcast_status(run)
      raise # Solid Queue records it; a retry no-ops (run no longer in_progress)
    end

    def scan_url(move, box, host, protocol)
      Rails.application.routes.url_helpers.move_scan_resolve_url(
        move, box.qr_token, host: host, protocol: protocol
      )
    end

    def filename(run)
      "boxes-#{format("%03d", run.from_number)}-#{format("%03d", run.to_number)}-labels.pdf"
    end
  end
end

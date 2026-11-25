# frozen_string_literal: true

require "stringio"

module LabelPrintRuns
  # Renders a bulk label-print PDF in the background, reporting live progress (#303).
  # Restores the Apartment tenant (jobs never inherit the request tenant), builds
  # BoxLabelsPdf box-by-box — reporting each box via LabelPrintRuns::RecordProgress
  # (throttled to ~20 broadcasts) — then attaches the finished PDF to the run and
  # finalizes it. The QR scan URLs are built from the request `host`/`protocol`
  # passed in at enqueue, since a job has no request of its own.
  #
  # Failure handling (#306). Errors that a second attempt can clear are retried
  # by ActiveJob, and the run stays `processing` meanwhile, so the live status
  # page keeps showing progress. Rendering restarts from the first box. The run
  # turns `failed` (and the "Try again" button shows) in one place, after_discard,
  # which ActiveJob calls when a transient error has used up its attempts and
  # immediately for any other error. Should that write itself fail (the
  # database is down for the last attempt), LabelPrintRuns::FailStale fails the
  # run on a later sweep (#985).
  class GenerateJob < ApplicationJob
    queue_as :default

    # Errors worth another attempt. Prawn itself renders deterministically, so
    # "render hiccups" are the database interruptions the render loop can meet
    # while it records progress. The rest are storage-client and network
    # failures from the Active Storage upload. Net::OpenTimeout, ReadTimeout and
    # WriteTimeout are Timeout::Error subclasses. The Aws names are strings
    # because aws-sdk-s3 loads only with the S3 service (`require: false`);
    # rescue_from resolves them when an error is raised and skips any name that
    # is not defined.
    TRANSIENT_ERRORS = [
      ActiveRecord::Deadlocked, ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled,
      ActiveRecord::ConnectionNotEstablished,
      ActiveStorage::IntegrityError,
      Timeout::Error, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
      Errno::EHOSTUNREACH, Errno::EPIPE, SocketError,
      "Seahorse::Client::NetworkingError",
      "Aws::S3::Errors::InternalError", "Aws::S3::Errors::ServiceUnavailable",
      "Aws::S3::Errors::SlowDown", "Aws::S3::Errors::RequestTimeout"
    ].freeze
    ATTEMPTS = 3

    # Without a block, retry_on runs after_discard and re-raises once the
    # attempts are used up, so Solid Queue still records the final error.
    retry_on(*TRANSIENT_ERRORS, wait: :polynomially_longer, attempts: ATTEMPTS)

    # Runs on the job instance (instance_exec), so it reads @run and @tenant.
    after_discard { |_job, _error| finalize_failed }

    # copies defaults to DEFAULT_COPIES so a job enqueued before Phase 45 deployed
    # (without the arg) still renders the prior fixed 2 pages per box.
    def perform(run_id, tenant:, host:, protocol:, box_ids:, copies: BoxLabelsPdf::DEFAULT_COPIES)
      @tenant = tenant
      Apartment::Tenant.switch(tenant) do
        Current.tenant = tenant
        run = LabelPrintRun.find_by(id: run_id)
        return unless run&.in_progress? # gone, or a retry after it already finished/failed

        @run = run
        generate(run, host, protocol, box_ids, copies)
      end
    end

    private

    def generate(run, host, protocol, box_ids, copies)
      # Render exactly the ids Start snapshotted + validated (in print order), so the
      # PDF always matches total_count even if the range changed since enqueue (#303).
      entries = run.move.boxes.where(id: box_ids).ordered.includes(:room).map do |box|
        { box: box, scan_url: scan_url(run.move, box, host, protocol) }
      end
      step = [run.total_count / 20, 1].max
      pdf = BoxLabelsPdf.new(entries: entries, copies: copies).render do |done, total|
        RecordProgress.new.call(run_id: run.id, completed: done) if (done % step).zero? || done == total
      end
      run.document.attach(io: StringIO.new(pdf), filename: filename(run), content_type: "application/pdf")
      run.update!(status: "completed", completed_count: run.total_count, finished_at: Time.current)
      Broadcasting.broadcast_status(run)
      reap_if_deleted(run)
    end

    # Marks the run failed and pushes the failed state (with "Try again") to the
    # status page. ActiveJob re-raises the error afterwards, so Solid Queue
    # records it, and a later run of this job no-ops because the run is no
    # longer in progress.
    #
    # Each retry is a fresh job instance, so when this attempt died before it
    # loaded the run (a database error at the lookup) @run is unset and the run
    # is looked up again from the job arguments (#985). If that lookup or the
    # failed write cannot reach the database either, LabelPrintRuns::FailStale
    # fails the run on a later sweep.
    def finalize_failed
      Apartment::Tenant.switch(tenant_from_arguments) do
        @run ||= active_run_from_arguments
        next unless @run

        mark_failed(@run)
        reap_if_deleted(@run)
      end
    rescue Apartment::TenantNotFound
      # The tenant schema was dropped (account deletion): the run row went with
      # it, so purge the attachment this job may have written to public.
      @run&.document&.purge
    rescue ActiveRecord::ActiveRecordError => e
      # The database is unreachable even for the tenant switch. Let ActiveJob
      # re-raise the job's own error (not this one) so Solid Queue records the
      # real cause; FailStale fails the run once the database is back.
      Rails.logger.warn("[label_print] could not finalize run=#{arguments.first}: #{e.class}: #{e.message}")
    end

    def tenant_from_arguments
      @tenant || arguments.last[:tenant]
    end

    def active_run_from_arguments
      run = LabelPrintRun.find_by(id: arguments.first)
      run if run&.in_progress?
    rescue ActiveRecord::ActiveRecordError => e
      # Still no database: leave the run to the FailStale sweep.
      Rails.logger.warn("[label_print] run lookup failed for run=#{arguments.first}: #{e.class}: #{e.message}")
      nil
    end

    def mark_failed(run)
      run.update!(status: "failed", finished_at: Time.current)
      Broadcasting.broadcast_status(run)
    rescue ActiveRecord::ActiveRecordError
      # The run row (or its whole tenant schema) vanished mid-job: nothing to
      # finalize. The caller still reaps, so an attached PDF can't orphan.
    end

    # Move/tenant deletion can race this job (#703 found the class): the
    # deletion actions capture attachment ids BEFORE deleting rows, so an
    # attach landing after that capture would strand the blob in the public
    # schema forever. Re-check after finalizing and reap our own work.

    def reap_if_deleted(run)
      return if LabelPrintRun.exists?(run.id)

      run.document.purge
    rescue ActiveRecord::StatementInvalid
      # Tenant schema dropped mid-job (account deletion) — the run row is gone
      # with its schema; purge the attachment just written to public.
      run.document.purge
    end

    def scan_url(move, box, host, protocol)
      Rails.application.routes.url_helpers.move_scan_resolve_url(
        move, box.qr_token, host: host, protocol: protocol
      )
    end

    def filename(run)
      "boxes-#{Box.pad_number(run.from_number)}-#{Box.pad_number(run.to_number)}-labels.pdf"
    end
  end
end

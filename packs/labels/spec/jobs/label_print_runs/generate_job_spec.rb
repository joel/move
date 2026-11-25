# frozen_string_literal: true

require "rails_helper"

RSpec.describe LabelPrintRuns::GenerateJob do
  let(:move) { create(:move) }
  let(:tenant) { Apartment::Tenant.current }

  before { [1, 2, 3].each { |n| create(:box, :with_room, move:, number: n.to_s, qr_token: "tok-#{n}") } }

  def ids_in(from, to)
    move.boxes.in_number_range(from, to).ids
  end

  def run_for(from, to)
    create(:label_print_run, move:, from_number: from, to_number: to,
                             total_count: ids_in(from, to).size, status: "processing")
  end

  it "renders the PDF, attaches it, and completes the run" do
    run = run_for(1, 3)

    described_class.perform_now(run.id, tenant:, host: "acme.example.com", protocol: "https", box_ids: ids_in(1, 3))

    run.reload
    expect(run.status).to eq("completed")
    expect(run.completed_count).to eq(3)
    expect(run.document).to be_attached
    expect(run.document.download[0, 4]).to eq("%PDF")
    expect(run.document.content_type).to eq("application/pdf")
  end

  it "renders the snapshotted ids even if a box leaves the range after enqueue (#304)" do
    run = run_for(1, 3)
    ids = ids_in(1, 3)
    move.boxes.find_by(number: "2").destroy # one box removed after the snapshot

    described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids)

    # The PDF renders only the boxes that still exist (2 of the 3 snapshotted), and
    # the run still finalizes to its announced total_count.
    expect(run.reload.status).to eq("completed")
    expect(run.completed_count).to eq(3)
    expect(run.document.download).to include("/Count 4") # 2 boxes × 2 pages
  end

  it "builds QR scan URLs against the passed host (a job has no request)" do
    run = run_for(1, 1)
    allow(BoxLabelsPdf).to receive(:new).and_call_original

    described_class.perform_now(run.id, tenant:, host: "acme.move-easy.org", protocol: "https", box_ids: ids_in(1, 1))

    expect(BoxLabelsPdf).to have_received(:new) do |entries:, **|
      expect(entries.first[:scan_url]).to start_with("https://acme.move-easy.org/")
    end
  end

  it "renders `copies` pages per box from the passed argument (Phase 45)" do
    run = run_for(1, 3)

    described_class.perform_now(
      run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3), copies: 3
    )

    expect(run.reload.document.download).to include("/Count 9") # 3 boxes × 3 copies
  end

  it "defaults to 2 copies when no copies arg is passed (pre-Phase-45 in-flight job)" do
    run = run_for(1, 3)

    described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3))

    expect(run.reload.document.download).to include("/Count 6") # 3 boxes × 2 default copies
  end

  describe "retrying transient failures (#306)" do
    include ActiveJob::TestHelper

    # The test env runs jobs inline, and the inline adapter cannot schedule the
    # delayed re-enqueue a retry needs. The test adapter can.
    def queue_adapter_for_test
      ActiveJob::QueueAdapters::TestAdapter.new
    end

    let(:pdf) { instance_double(BoxLabelsPdf) }
    let(:statuses_seen) { [] }

    before do
      allow(BoxLabelsPdf).to receive(:new).and_return(pdf)
      allow(LabelPrintRuns::Broadcasting).to receive(:broadcast_status).and_call_original
    end

    # Performs the job and every retry it schedules. The block form of
    # perform_enqueued_jobs would wrap the final error in a Minitest assertion.
    def enqueue_and_drain(run)
      described_class.perform_later(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3))
      perform_enqueued_jobs while enqueued_jobs.any?
    end

    # Each render records the run's persisted status before acting, so a spec
    # can show the run stayed active between attempts.
    def render_with(run, outcomes)
      allow(pdf).to receive(:render) do
        statuses_seen << LabelPrintRun.find(run.id).status
        outcome = outcomes.shift
        raise outcome if outcome.is_a?(Exception)

        outcome
      end
    end

    it "retries a transient error, keeps the run processing, and then completes" do
      run = run_for(1, 3)
      render_with(run, [Errno::ECONNRESET.new("storage reset"), "%PDF-1.4 fake"])

      enqueue_and_drain(run)

      expect(pdf).to have_received(:render).twice
      expect(statuses_seen).to eq(%w[processing processing])
      expect(run.reload.status).to eq("completed")
      expect(run.document).to be_attached
      expect(LabelPrintRuns::Broadcasting).not_to have_received(:broadcast_status)
        .with(having_attributes(status: "failed"))
    end

    it "fails the run only once its transient retries are exhausted" do
      run = run_for(1, 3)
      errors = Array.new(described_class::ATTEMPTS) { ActiveStorage::IntegrityError.new("checksum") }
      render_with(run, errors)

      expect { enqueue_and_drain(run) }.to raise_error(ActiveStorage::IntegrityError)

      expect(pdf).to have_received(:render).exactly(described_class::ATTEMPTS).times
      expect(statuses_seen).to all(eq("processing"))
      expect(run.reload.status).to eq("failed")
      expect(run.finished_at).to be_present
      expect(LabelPrintRuns::Broadcasting).to have_received(:broadcast_status)
        .with(having_attributes(status: "failed")).once
    end

    it "fails the run at once on a non-transient error, without retrying" do
      run = run_for(1, 3)
      render_with(run, [ArgumentError.new("bad layout")])

      expect { enqueue_and_drain(run) }.to raise_error(ArgumentError, "bad layout")

      expect(pdf).to have_received(:render).once
      expect(run.reload.status).to eq("failed")
      expect(LabelPrintRuns::Broadcasting).to have_received(:broadcast_status)
        .with(having_attributes(status: "failed")).once
    end

    describe "when the database fails on the last attempt (#985)" do
      let(:stale_later) { LabelPrintRuns::FailStale::STALE_AFTER + 1.minute }

      # Every attempt dies at the run lookup, so no attempt ever sets @run.
      # The first `failing_lookups` calls to find_by raise; later ones succeed.
      def break_run_lookup(failing_lookups)
        calls = 0
        allow(LabelPrintRun).to receive(:find_by).and_wrap_original do |original, *args, **kwargs|
          calls += 1
          raise ActiveRecord::ConnectionNotEstablished, "db down" if calls <= failing_lookups

          original.call(*args, **kwargs)
        end
      end

      it "fails the run from the job arguments once the database answers again" do
        run = run_for(1, 3)
        break_run_lookup(described_class::ATTEMPTS)

        expect { enqueue_and_drain(run) }.to raise_error(ActiveRecord::ConnectionNotEstablished)

        expect(BoxLabelsPdf).not_to have_received(:new)
        expect(run.reload.status).to eq("failed")
        expect(LabelPrintRuns::Broadcasting).to have_received(:broadcast_status)
          .with(having_attributes(status: "failed")).once
      end

      it "leaves the run to the FailStale sweep when the database is still down, which fails it later" do
        run = run_for(1, 3)
        break_run_lookup(described_class::ATTEMPTS + 1)

        expect { enqueue_and_drain(run) }.to raise_error(ActiveRecord::ConnectionNotEstablished)
        expect(run.reload.status).to eq("processing")

        travel(stale_later) { LabelPrintRuns::FailStale.new.call }

        expect(run.reload.status).to eq("failed")
      end

      it "recovers a run whose failed write raises, on a later sweep" do
        run = run_for(1, 3)
        loaded = LabelPrintRun.find(run.id)
        allow(loaded).to receive(:update!).and_raise(ActiveRecord::ConnectionNotEstablished, "db down")
        allow(LabelPrintRun).to receive(:find_by).and_return(loaded)
        render_with(run, [ArgumentError.new("bad layout")])

        expect { enqueue_and_drain(run) }.to raise_error(ArgumentError, "bad layout")
        expect(run.reload.status).to eq("processing")

        allow(LabelPrintRun).to receive(:find_by).and_call_original
        travel(stale_later) { LabelPrintRuns::FailStale.new.call }

        expect(run.reload.status).to eq("failed")
      end
    end
  end

  it "marks the run failed (and re-raises) when rendering blows up" do
    run = run_for(1, 3)
    pdf = instance_double(BoxLabelsPdf)
    allow(BoxLabelsPdf).to receive(:new).and_return(pdf)
    allow(pdf).to receive(:render).and_raise(StandardError, "boom")

    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 3))
    end.to raise_error(StandardError)
    expect(run.reload.status).to eq("failed")
  end

  it "reaps its own attachment when the run is deleted and the job then fails (#703)" do
    run = run_for(1, 1)
    run.document.attach(io: StringIO.new("%PDF-1.4 partial"), filename: "x.pdf", content_type: "application/pdf")
    pdf = instance_double(BoxLabelsPdf)
    allow(BoxLabelsPdf).to receive(:new).and_return(pdf)
    allow(pdf).to receive(:render) do
      LabelPrintRun.where(id: run.id).delete_all
      raise ArgumentError, "boom"
    end

    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids_in(1, 1))
    end.to raise_error(ArgumentError)
    expect(
      ActiveStorage::Attachment.where(record_type: "LabelPrintRun", record_id: run.id)
    ).to be_empty
  end

  it "no-ops on a run that is no longer in progress (a retry after completion)" do
    run = create(:label_print_run, :completed, move:, total_count: 3)
    expect do
      described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: [])
    end.not_to(change { run.reload.updated_at })
  end

  it "reaps its own attachment when the run was deleted while rendering (#703)" do
    run = run_for(1, 1)
    ids = ids_in(1, 1)
    fake = instance_double(BoxLabelsPdf)
    allow(BoxLabelsPdf).to receive(:new).and_return(fake)
    allow(fake).to receive(:render) do
      LabelPrintRun.where(id: run.id).delete_all
      "%PDF-1.4 fake"
    end

    described_class.perform_now(run.id, tenant:, host: "h", protocol: "https", box_ids: ids)

    expect(
      ActiveStorage::Attachment.where(record_type: "LabelPrintRun", record_id: run.id)
    ).to be_empty
  end
end

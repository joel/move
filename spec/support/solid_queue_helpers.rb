# frozen_string_literal: true

# A real Solid Queue for examples that must read queue records (#990). The test
# database has no Solid Queue tables, so the shared context creates them from
# db/queue_structure.sql inside the example's transaction (PostgreSQL DDL is
# transactional, so the rollback drops them) and points `job_class` at the Solid
# Queue adapter. Production keeps these tables in a separate queue database;
# here they sit beside the app tables, which no queue query joins.
module SolidQueueHelpers
  # The dump's table, sequence, constraint and index statements. Its session
  # settings and Rails metadata tables are left out.
  QUEUE_DDL = /\A(?:CREATE|ALTER)\b.*\bsolid_queue_/m

  def create_solid_queue_tables
    dump = Rails.root.join("db/queue_structure.sql").read.gsub(/^--.*$/, "")
    statements = dump.split(/;$/).map(&:strip).grep(QUEUE_DDL)
    statements.each { |statement| ActiveRecord::Base.connection.execute(statement) }
  end

  # Takes the next ready job as a worker would: call `perform` on the result to
  # run it, or `failed_with` to record the failure of a lost worker.
  def claim_next_job
    SolidQueue::ReadyExecution.claim("*", 1, nil).first
  end
end

RSpec.shared_context "with a real Solid Queue" do
  before do
    create_solid_queue_tables
    # Stubbed, not assigned: an adapter set on the job class would outlive the
    # example and shadow the test adapter other specs set on ActiveJob::Base.
    adapter = ActiveJob::QueueAdapters.lookup(:solid_queue).new
    allow(job_class).to receive_messages(queue_adapter: adapter, queue_adapter_name: "solid_queue")
    # A lookup that raises also leaves a run alone, so examples check it didn't.
    allow(Rails.logger).to receive(:warn).and_call_original
  end

  after { ActiveRecord::Base.connection.schema_cache.clear! }
end

RSpec.configure do |config|
  config.include SolidQueueHelpers
end

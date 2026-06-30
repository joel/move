# frozen_string_literal: true

module DemoData
  # Provisions the curated onboarding sample Move inside the active tenant schema
  # (#432). Builds a clearly-marked `sample` Move on the network-free `fake`
  # providers (recognition/search/image-gen all work with no key) and fills it from
  # a ~6-box subset of the committed demo catalog via DemoData::SampleBuilder — no
  # AI call, no cost. Idempotent: a second run (job retry, or a tenant that already
  # has its sample) is a no-op. The caller (DemoData::ProvisionJob) owns the tenant
  # switch and the org-level status/broadcast.
  class Provision < BaseAction
    # The curated subset: every lifecycle state (sealed/packing/in_transit), photos
    # with replayed recognition + a recovery tile (box 1), photo-less manual items
    # (boxes 2/5, incl. the semantic-search "Hair dryer"), and a fragile box (13).
    SAMPLE_BOX_NUMBERS = %w[1 2 3 5 11 13].freeze
    SAMPLE_MOVE_NAME = "Sample move"

    def call(owner:)
      existing = Move.find_by(sample: true)
      return Success(existing) if existing

      Success(provision(owner))
    end

    private

    # Create the Move and build its contents ATOMICALLY: if the build raises (image
    # attach, storage, …), the whole Move rolls back rather than leaving a half-built
    # `sample: true` Move that the index would show as real and that a retry — guarded
    # by `find_by(sample: true)` above — could never repair. On a rollback the job
    # marks the org "failed", the index shows the fallback card, and re-dispatch
    # starts clean. The build raises out to the job, which is the error boundary.
    def provision(owner)
      ActiveRecord::Base.transaction do
        move = Moves::Create.new.call(params: sample_params, creator: owner).value!
        DemoData::SampleBuilder.call(move: move, box_numbers: SAMPLE_BOX_NUMBERS)
        move
      end
    end

    def sample_params
      {
        name: SAMPLE_MOVE_NAME, status: "started", unit_system: "metric",
        recognition_provider: "fake", embedding_provider: "fake", image_provider: "fake",
        sample: true
      }
    end
  end
end

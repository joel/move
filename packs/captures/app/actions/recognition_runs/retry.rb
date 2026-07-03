# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: retries a recognition run (captures + recoveries controllers).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Retry a failed run by creating a *new* RecognitionRun for the same Media and
  # re-enqueuing (Domain §4.10). The original run is left as-is for the record.
  class Retry < BaseAction
    # Only a failed run is retryable — guards against double-submits / replayed
    # POSTs queuing a duplicate run (and duplicate items) for the same media.

    #: (run: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run:)
      return Failure(:not_retryable) unless run&.failed?

      yield ensure_writable(run.move)
      Enqueue.new.call(media: run.media)
    end
  end
end

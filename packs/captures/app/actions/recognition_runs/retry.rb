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
    # A failed run whose media already yielded kept items is NOT retryable
    # either (#649): under the atomic completion model a failed run commits no
    # inventory, so items sourced from this media mean another run already
    # materialized it (a pre-#649 legacy failed-with-inventory run, or a stale
    # tab retrying a media a later run succeeded on) — re-running would
    # duplicate every one of them.

    #: (run: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run:)
      return Failure(:not_retryable) unless run&.failed?
      return Failure(:not_retryable) if Item.kept.exists?(source_media_id: run.media_id)

      yield ensure_writable(run.move)
      Enqueue.new.call(media: run.media)
    end
  end
end

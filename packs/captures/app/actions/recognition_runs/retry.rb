# frozen_string_literal: true

# pack_public: true -- public API of packs/recognition: retries a recognition run (captures + recoveries controllers).
# Kept in its layer (not app/public) so the architecture fitness tests keep
# governing it; the sigil exposes it past enforce_privacy. See packwerk-boundaries.md.

module RecognitionRuns
  # Retry a failed run by creating a *new* RecognitionRun for the same Media and
  # re-enqueuing (Domain §4.10). The original run is left as-is for the record.
  # The new run inherits the failed run's `rescan` flag (#897).
  class Retry < BaseAction
    # Only a failed run is retryable — guards against double-submits / replayed
    # POSTs queuing a duplicate run (and duplicate items) for the same media.
    # A failed run whose photo was already materialized is NOT retryable
    # either (#649): under the atomic completion model a failed run commits no
    # inventory, so kept items sourced from this photo mean another run already
    # materialized it (a pre-#649 legacy failed-with-inventory run, or a stale
    # tab retrying a media a later run succeeded on) — re-running would
    # duplicate every one of them. A retake re-scan run is judged on the items
    # of the current image only (RecognitionRun#materialized_items), so the
    # retake's "retry from the capture screen" recovery works.
    # Only the photo's latest run is retryable (#902): once a newer run exists
    # (say a retry that succeeded with nothing detected), the old failure is
    # history, and re-running it would re-scan a photo that already has a
    # result — and a failure there would replace that good result.
    #
    # The checks run again under the photo lock that Enqueue takes for the
    # guard (#896): two concurrent retries serialize there, and the second
    # sees the first's queued run and is refused.

    #: (run: untyped) -> Dry::Monads::Result[untyped, untyped]
    def call(run:)
      return Failure(:not_retryable) unless retryable?(run)

      yield ensure_writable(run.move)
      Enqueue.new.call(media: run.media, rescan: run.rescan?, guard: ->(_media) { recheck(run) })
    end

    private

    #: (untyped run) -> bool
    def retryable?(run)
      !run.nil? && run.failed? && RecognitionRun.latest_for?(run) && !run.materialized_items.exists?
    end

    # Under the photo lock: the run is still failed and still the photo's
    # latest, nothing has materialized the photo since the pre-check, and no
    # newer run is already in flight.

    #: (untyped run) -> Dry::Monads::Result[untyped, untyped]
    def recheck(run)
      run.reload
      return Failure(:not_retryable) unless retryable?(run)
      return Failure(:not_retryable) if RecognitionRun.exists?(media_id: run.media_id, status: RecognitionRun::IN_FLIGHT)

      Success()
    end
  end
end

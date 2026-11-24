# frozen_string_literal: true

# Makes every job enqueue raise, as a Solid Queue outage does (#955):
# SolidQueue::Job::EnqueueError is a plain StandardError, so it escapes
# perform_later instead of turning into `false`.
module QueueFailureHelpers
  def fail_every_enqueue
    adapter = ActiveJob::Base.queue_adapter
    allow(adapter).to receive(:enqueue).and_raise(SolidQueue::Job::EnqueueError, "queue down")
    allow(adapter).to receive(:enqueue_at).and_raise(SolidQueue::Job::EnqueueError, "queue down")
  end
end

RSpec.configure do |config|
  config.include QueueFailureHelpers
end

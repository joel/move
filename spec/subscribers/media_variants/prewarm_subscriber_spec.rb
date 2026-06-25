require "rails_helper"

RSpec.describe MediaVariants::PrewarmSubscriber do
  subject(:subscriber) { described_class.new }

  before { allow(MediaVariants::PrewarmJob).to receive(:perform_later) }

  def event(name, payload)
    { name: name, payload: payload }
  end

  it "enqueues a prewarm job for media.captured with the current tenant" do
    subscriber.emit(event("media.captured", { media_id: "abc-123" }))

    expect(MediaVariants::PrewarmJob).to have_received(:perform_later)
      .with("abc-123", tenant: Apartment::Tenant.current)
  end

  it "ignores events without a media_id" do
    subscriber.emit(event("media.captured", {}))

    expect(MediaVariants::PrewarmJob).not_to have_received(:perform_later)
  end

  it "swallows an enqueue failure so it can't break the emitting capture (§1#4)" do
    allow(MediaVariants::PrewarmJob).to receive(:perform_later).and_raise(StandardError, "queue down")

    expect { subscriber.emit(event("media.captured", { media_id: "abc-123" })) }.not_to raise_error
  end
end

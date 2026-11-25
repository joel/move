# frozen_string_literal: true

require "rails_helper"

RSpec.describe Components::Ui::CameraViewfinder do
  it "renders the portrait frame with an inline, muted, autoplaying cover video" do
    html = described_class.new(controller: "camera-capture").call

    expect(html).to start_with(
      '<div class="relative aspect-3/4 w-full overflow-hidden rounded-card bg-black">'
    )
    expect(html).to include(
      '<video class="h-full w-full object-cover" playsinline muted autoplay ' \
      'data-camera-capture-target="video"></video>'
    )
  end

  it "makes the video the named controller's video target" do
    html = described_class.new(controller: "qr-scanner").call
    expect(html).to include('data-qr-scanner-target="video"')
  end

  it "appends the caller's layout classes and wrapper data" do
    html = described_class.new(
      controller: "camera-capture", css: "mx-auto hidden max-w-md",
      data: { "camera-capture-target": "viewfinder" }
    ).call

    expect(html).to include(
      'class="relative aspect-3/4 w-full overflow-hidden rounded-card bg-black mx-auto hidden max-w-md"'
    )
    expect(html).to include('data-camera-capture-target="viewfinder"')
  end

  it "renders the overlay block after the video, inside the frame" do
    html = described_class.new(controller: "qr-scanner").call do |c|
      c.div(class: "absolute inset-0") { "OVERLAY" }
    end

    expect(html).to match(%r{</video><div class="absolute inset-0">OVERLAY</div></div>\z})
  end

  it "builds the Turbo-cache teardown/resume actions for a consumer controller (#987)" do
    expect(described_class.cache_actions("qr-scanner")).to eq(
      "turbo:before-cache@document->qr-scanner#teardown " \
      "turbo:load@document->qr-scanner#resume " \
      "turbo:render@document->qr-scanner#resume " \
      "popstate@window->qr-scanner#resume"
    )
  end

  it "exposes the shutter recipe with disabled and focus-visible states" do
    expect(described_class::SHUTTER_CLASSES).to include(
      "disabled:opacity-50", "focus-visible:outline-accent-sage", "active:scale-90"
    )
  end
end

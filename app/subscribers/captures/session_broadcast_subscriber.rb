# frozen_string_literal: true

module Captures
  # Pushes the capture "Items" panel live as recognition progresses (#241),
  # replacing the old 2.5s polling controller. RecognitionRuns::Process emits
  # recognition_run.{processing,succeeded,failed} as each run advances; this
  # re-renders the box's SessionPanel and broadcasts it over ActionCable / Turbo
  # Streams (the mechanism PR2 #239 established), so the panel updates without a
  # reload and with no polling.
  #
  # Runs synchronously inside the emitting Refresh/ProcessJob, so
  # Apartment::Tenant.current is still the tenant. The signed stream name is bound
  # to the tenant-unique Box; the replace target is the panel's stable DOM id.
  class SessionBroadcastSubscriber
    RUN_EVENTS = %w[recognition_run.processing recognition_run.succeeded recognition_run.failed].freeze

    def emit(event)
      return unless RUN_EVENTS.include?(event[:name])

      run_id = event[:payload]&.dig(:recognition_run_id)
      return if run_id.blank?

      run = RecognitionRun.includes(box: :move).find_by(id: run_id)
      return if run.nil?

      Turbo::StreamsChannel.broadcast_replace_to(
        run.box, :recognition,
        target: Views::Captures::SessionPanel::ID,
        html: ApplicationController.render(Captures::SessionContent.new(run.box).panel, layout: false)
      )
    end
  end
end

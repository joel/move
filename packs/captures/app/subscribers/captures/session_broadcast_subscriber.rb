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
    # A person settling a conflict (#881) changes the photo's card too: the
    # "Already in this box" caption gives way to the normal states.
    CONFLICT_EVENTS = %w[recognition_suggestion.conflict_dismissed recognition_suggestion.conflict_kept_both].freeze

    def emit(event)
      box = box_for(event)
      broadcast(box) if box
    end

    private

    def box_for(event)
      payload = event[:payload] || {}
      if RUN_EVENTS.include?(event[:name])
        run_id = payload[:recognition_run_id]
        RecognitionRun.includes(box: :move).find_by(id: run_id)&.box if run_id.present?
      elsif CONFLICT_EVENTS.include?(event[:name]) && payload[:box_id].present?
        Box.find_by(id: payload[:box_id])
      end
    end

    # This runs synchronously inside RecognitionRuns::Process (it emits the events),
    # so a render/broadcast failure must NEVER propagate — Process would rescue it
    # and mark the run failed, turning a cosmetic panel glitch into a lost
    # recognition. Isolate it: the worst case is a missed live update, and the next
    # event (or a reload) re-renders the panel.
    def broadcast(box)
      Turbo::StreamsChannel.broadcast_replace_to(
        box, :recognition,
        target: Views::Captures::SessionPanel::ID,
        html: ApplicationController.render(Captures::SessionContent.new(box).panel, layout: false)
      )
    rescue StandardError => e # rubocop:disable Move/BroadRescue -- §1#4 broadcast must not break emitter
      Rails.logger.warn("[captures] session panel broadcast failed: #{e.class}: #{e.message}")
    end
  end
end

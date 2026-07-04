# frozen_string_literal: true

module Ui
  # Lookbook scenarios for Components::Ui::RecognitionState (#530) — the single
  # source of truth for the seven recognition states.
  class RecognitionStatePreview < Lookbook::Preview
    # @!group States

    def queued
      render Components::Ui::RecognitionState.new(state: :queued)
    end

    def processing
      render Components::Ui::RecognitionState.new(state: :processing)
    end

    def succeeded
      render Components::Ui::RecognitionState.new(state: :succeeded)
    end

    def failed
      render Components::Ui::RecognitionState.new(state: :failed)
    end

    def needs_correction
      render Components::Ui::RecognitionState.new(state: :needs_correction)
    end

    def auto_confirmed
      render Components::Ui::RecognitionState.new(state: :auto_confirmed)
    end

    def pending_review
      render Components::Ui::RecognitionState.new(state: :pending_review)
    end

    # @!endgroup

    # The failed badge grows a Retry overlay when a retry_href is given.
    def failed_with_retry
      render Components::Ui::RecognitionState.new(state: :failed, retry_href: "#")
    end
  end
end

# frozen_string_literal: true

module Components
  module Ui
    # Customer-safe failure copy for a failed recognition run, shared by the
    # capture session panel and the photo recovery view. Known categories
    # (quota / rate limit / auth / network) map to a localized line; an
    # unrecognized failure falls back to the cleaned vendor detail
    # (RecognitionRun#error_detail), else the generic line. Never leaks adapter
    # class names or status codes.
    #
    #   render Components::Ui::RecognitionErrorCaption.new(run: run)
    class RecognitionErrorCaption < Components::Base
      def initialize(run:, css: "text-body-md text-error")
        @run = run
        @css = css
      end

      def view_template
        p(class: @css) { caption_text }
      end

      private

      def caption_text
        body =
          if @run.error_category == :generic
            @run.error_detail
          else
            I18n.t("ui.recognition_errors.#{@run.error_category}")
          end
        body.presence || I18n.t("ui.recognition_errors.generic")
      end
    end
  end
end

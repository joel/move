# frozen_string_literal: true

# Sink for browser CSP violation reports (#493). The report-only rollout points the
# policy's `report-uri` here so violations are collected in the app logs — letting us
# confirm prod (especially Google One Tap + ActionCable, which can't be exercised in
# dev) is violation-free before flipping the policy to enforcing.
#
# Browsers post reports without credentials, so this is public + unauthenticated
# (ActionController::API — no session, no CSRF, no tenant/terms gate). It reads a
# bounded body and logs only a structured, `inspect`-escaped summary (so a crafted
# report can't inject log lines or exhaust memory); it never trusts the body further.
class CspReportsController < ActionController::API
  MAX_REPORT_BYTES = 8_192

  # POST /csp-violation-report  (Content-Type: application/csp-report)
  def create
    report = parse_report(request.body.read(MAX_REPORT_BYTES).to_s)
    if report
      Rails.logger.warn(
        "[csp-violation] directive=#{report["violated-directive"].inspect} " \
        "blocked=#{report["blocked-uri"].inspect} document=#{report["document-uri"].inspect}"
      )
    end
    head :no_content
  end

  private

  # The report body is `{"csp-report": {...}}`; return that inner hash, or nil for
  # anything malformed (bad JSON, wrong shape) — never raise on hostile input.
  def parse_report(raw)
    parsed = JSON.parse(raw)
    parsed["csp-report"] if parsed.is_a?(Hash) && parsed["csp-report"].is_a?(Hash)
  rescue JSON::ParserError
    nil
  end
end

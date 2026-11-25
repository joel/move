# frozen_string_literal: true

# A fake rear camera for `:js` specs of the in-app camera surfaces (#619,
# #987, #991, #992). The script is injected over CDP BEFORE any page script
# runs (controllers read CameraStream.supported at connect, and the lvh.me
# test host is an insecure context with no navigator.mediaDevices at all) and
# serves a canvas captureStream() as the camera. Browser-side knobs on
# `window.__camera`:
#
#   deny = true    the next getUserMedia rejects like a permission denial
#   hold = true    getUserMedia waits until `release()` (an open permission
#                  prompt); `deny` is read at release time
#   calls/streams  how often the camera was requested, and what it served
#
# Install it from a `before` (the :js driver switch is itself a before hook,
# so inside `around` the session is still rack_test); the `after` removes the
# script again so it never leaks into another spec on the reused Chrome.
module FakeCameraHelpers
  FAKE_CAMERA_JS = <<~JS
    (() => {
      const camera = window.__camera = { calls: 0, deny: false, hold: false, held: [], streams: [] }
      if (!navigator.mediaDevices) {
        Object.defineProperty(navigator, "mediaDevices", { value: {}, configurable: true })
      }
      // The insecure origin answers the camera permission query "denied",
      // which CameraStream treats as sticky — report a fresh "prompt" so
      // every start() reaches getUserMedia (and the deny flag decides).
      if (navigator.permissions) {
        const query = navigator.permissions.query.bind(navigator.permissions)
        navigator.permissions.query = (descriptor) =>
          descriptor?.name === "camera" ? Promise.resolve({ state: "prompt" }) : query(descriptor)
      }
      const serve = () => {
        if (camera.deny) throw new DOMException("Permission denied", "NotAllowedError")
        const canvas = document.createElement("canvas")
        canvas.width = 640
        canvas.height = 480
        const ctx = canvas.getContext("2d")
        const paint = () => { ctx.fillStyle = "#6b8f71"; ctx.fillRect(0, 0, 640, 480) }
        paint()
        setInterval(paint, 100)
        const stream = canvas.captureStream(10)
        camera.streams.push(stream)
        return stream
      }
      camera.release = () => camera.held.splice(0).forEach((resume) => resume())
      camera.liveTrack = (index) => camera.streams[index]?.getVideoTracks()[0]?.readyState === "live"
      navigator.mediaDevices.getUserMedia = async () => {
        camera.calls++
        if (camera.hold) await new Promise((resolve) => camera.held.push(resolve))
        return serve()
      }
    })()
  JS

  def install_fake_camera
    @fake_camera_script = page.driver.browser.execute_cdp(
      "Page.addScriptToEvaluateOnNewDocument", source: FAKE_CAMERA_JS
    )
  end

  def remove_fake_camera
    return unless @fake_camera_script

    page.driver.browser.execute_cdp(
      "Page.removeScriptToEvaluateOnNewDocument", identifier: @fake_camera_script["identifier"]
    )
    @fake_camera_script = nil
  end

  def camera(expr) = page.evaluate_script("window.__camera.#{expr}")

  # Retry a cross-thread/browser read until it holds.
  def eventually(timeout: 10)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    loop do
      return true if yield
      raise "condition not met within #{timeout}s" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      sleep 0.1
    end
  end

  # Turbo's empty-state history pop (#987): a fragment change made outside
  # Turbo fires popstate with no Turbo state, so Turbo caches the page
  # (turbo:before-cache) without rendering anything over it.
  def pop_history_outside_turbo
    page.execute_script("window.location.hash = 'outside-turbo'")
  end

  # Turbo caching the page and then rendering without replacing it (e.g. a
  # morphing refresh) — the turbo:render branch of #987.
  def cache_then_render_in_place
    page.execute_script(<<~JS)
      document.dispatchEvent(new Event("turbo:before-cache"))
      document.dispatchEvent(new Event("turbo:render"))
    JS
  end
end

RSpec.configure do |config|
  config.include FakeCameraHelpers, type: :system
end

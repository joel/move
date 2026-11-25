// #618 — the one getUserMedia/stream lifecycle shared by every in-app camera
// surface (camera_capture_controller on B2 capture, qr_scanner_controller on
// E2 scan). It owns acquire → attach → release for a single <video>, and the
// two invariants both surfaces need:
//
//   1. A generation token per start(). stop() bumps it, and every await tail
//      (permission query, getUserMedia, play()) re-checks it — so a teardown
//      while the permission prompt is open (Turbo navigation, page hide)
//      stops the late-arriving stream instead of leaving the camera lit on a
//      detached element.
//   2. Track-ended recovery: `ended` listeners are attached BEFORE play() (a
//      track can die in the play() window) and only the current generation's
//      tracks reach `onEnded` — the caller decides whether to retry, wait, or
//      fall back.
//
// start() resolves to one outcome, and never rejects:
//   "live"        streaming into the video, frames rendering
//   "unavailable" denied (sticky or at the prompt), no device, dead track, or
//                 play() refused — nothing is left running
//   "stale"       superseded by stop()/start() while awaiting — ignore it; the
//                 caller that superseded it owns the state now
export default class CameraStream {
  static get supported() {
    return !!navigator.mediaDevices?.getUserMedia
  }

  // video: the <video> to stream into (Ui::CameraViewfinder renders it).
  // constraints: the getUserMedia `video` constraints (rear camera by default).
  // onEnded: called once when a live track of the current stream dies.
  constructor(video, { constraints = { facingMode: "environment" }, onEnded = () => {} } = {}) {
    this.video = video
    this.constraints = constraints
    this.onEnded = onEnded
    this.generation = 0
    this.stream = null
  }

  // True while the token is still the latest — for the caller's own await
  // tails (e.g. a frame grab) that must not act after a teardown.
  isCurrent(generation) {
    return generation === this.generation
  }

  async start() {
    this.stop()
    const generation = this.generation
    // A sticky denial shouldn't re-prompt on every visit; browsers without the
    // camera permission query (Safari) fall through to getUserMedia itself.
    const denied = await this.#cameraDenied()
    if (!this.isCurrent(generation)) return "stale"
    if (denied || !CameraStream.supported) return "unavailable"
    let stream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: this.constraints })
    } catch (_error) {
      return this.isCurrent(generation) ? "unavailable" : "stale"
    }
    // Torn down (or superseded) while the permission prompt was open — the
    // fresh stream must not outlive its request.
    if (!this.isCurrent(generation)) {
      stopTracks(stream)
      return "stale"
    }
    this.stream = stream
    const tracks = stream.getVideoTracks()
    // Listen before play(): an 'ended' fired before attachment would strand
    // the caller "streaming" on a corpse.
    if (!tracks[0] || tracks[0].readyState !== "live") {
      this.#release()
      return "unavailable"
    }
    tracks.forEach((track) =>
      track.addEventListener("ended", () => {
        if (this.isCurrent(generation)) this.onEnded()
      })
    )
    this.video.srcObject = stream
    try {
      await this.video.play()
    } catch (_error) {
      // Autoplay refused even with muted/playsinline — a viewfinder that never
      // renders frames is not a live camera.
      if (!this.isCurrent(generation)) return "stale"
      this.#release()
      return "unavailable"
    }
    return this.isCurrent(generation) ? "live" : "stale"
  }

  // Release the camera and invalidate every in-flight start() tail. Idempotent
  // — safe from disconnect(), turbo:before-cache, visibility, and onEnded.
  stop() {
    this.generation++
    this.#release()
  }

  #release() {
    stopTracks(this.stream)
    this.stream = null
    if (this.video.srcObject) this.video.srcObject = null
  }

  async #cameraDenied() {
    try {
      const status = await navigator.permissions.query({ name: "camera" })
      return status.state === "denied"
    } catch (_error) {
      return false
    }
  }

}

function stopTracks(stream) {
  stream?.getTracks().forEach((track) => track.stop())
}

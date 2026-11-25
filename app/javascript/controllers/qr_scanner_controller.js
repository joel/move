import { Controller } from "@hotwired/stimulus"
import jsQR from "jsqr"
import CameraStream from "camera/stream"

// E2 — drives the live QR scanner. Opens the rear camera, decodes frames with
// jsQR, and navigates to the resolved token. A printed label's QR encodes the
// full resolve URL, so a camera hit navigates straight there; manual entry takes
// just the token and is appended to resolveUrlValue. If the camera is denied,
// unsupported, dies mid-scan, or the decode loop throws, the camera is released
// and the manual-entry fallback is revealed instead.
//
// The stream lifecycle is the shared camera/stream module (#618): its
// generation guard is what closes the permission-prompt race — a Turbo
// navigation while the prompt is open (disconnect / turbo:before-cache →
// teardown) makes the late getUserMedia resolve "stale" and stop its stream,
// instead of leaving the camera lit and the decode loop running against a
// detached element.
export default class extends Controller {
  static values = { resolveUrl: String }
  static targets = ["video", "canvas", "manual", "fallback"]

  connect() {
    this.scanning = false
    this.resumeAfterCache = false
    this.camera = new CameraStream(this.videoTarget, { onEnded: () => this.#unavailable() })
    this.#startCamera()
  }

  disconnect() {
    this.resumeAfterCache = false
    this.#stopCamera()
  }

  // turbo:before-cache — release the camera as soon as a navigation starts and
  // snapshot a pristine scanner (no revealed fallback), so a cache restore
  // reconnects into the same state a fresh visit would. Turbo can also cache
  // WITHOUT replacing the page (#987: a history entry Turbo didn't create, or
  // a morphing refresh) — then no disconnect/connect follows, so remember to
  // restart the camera if this controller is still connected afterwards.
  teardown() {
    this.#stopCamera()
    this.resumeAfterCache = true
    this.element.classList.remove("camera-unavailable")
    if (this.hasFallbackTarget) this.fallbackTarget.classList.add("hidden")
  }

  // turbo:load / turbo:render / popstate after a teardown: the page was not
  // replaced (this element is still mounted), so the camera comes back (or
  // the fallback is revealed) instead of a silent black viewfinder. popstate
  // covers Turbo's empty-state history pop, which caches the page but fires
  // neither turbo:load nor turbo:render. Deferred one tick: Turbo clones the
  // snapshot on the next event-loop tick after turbo:before-cache, and the
  // restart must not leak into it.
  resume() {
    if (!this.resumeAfterCache) return
    setTimeout(() => {
      if (!this.resumeAfterCache || !this.element.isConnected) return
      this.resumeAfterCache = false
      this.#startCamera()
    }, 0)
  }

  // Manual code entry (camera-independent fallback).
  submitManual(event) {
    event.preventDefault()
    const token = this.manualTarget.value.trim()
    if (token) this.#visit(`${this.resolveUrlValue}/${encodeURIComponent(token)}`)
  }

  async #startCamera() {
    if (!CameraStream.supported) return this.#revealFallback()
    const outcome = await this.camera.start()
    // Torn down while awaiting (navigated away mid-prompt) — the module has
    // already stopped the late stream; nothing here may touch the DOM.
    if (outcome === "stale") return
    if (outcome !== "live") return this.#revealFallback()
    this.scanning = true
    this.#tick()
  }

  #stopCamera() {
    this.scanning = false
    if (this.rafId) cancelAnimationFrame(this.rafId)
    this.rafId = null
    this.camera.stop()
  }

  // The camera died mid-scan or the decode loop failed — never leave a lit
  // camera behind a dead loop; hand over to manual entry.
  #unavailable() {
    this.#stopCamera()
    this.#revealFallback()
  }

  #tick() {
    if (!this.scanning) return
    let code
    try {
      code = this.#decodeFrame()
    } catch (_error) {
      return this.#unavailable()
    }
    if (code?.data) return this.#onDecode(code.data)
    this.rafId = requestAnimationFrame(() => this.#tick())
  }

  #decodeFrame() {
    const video = this.videoTarget
    if (video.readyState !== video.HAVE_ENOUGH_DATA) return null
    const canvas = this.canvasTarget
    canvas.width = video.videoWidth
    canvas.height = video.videoHeight
    const ctx = canvas.getContext("2d", { willReadFrequently: true })
    ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
    const image = ctx.getImageData(0, 0, canvas.width, canvas.height)
    return jsQR(image.data, image.width, image.height)
  }

  #onDecode(data) {
    this.#stopCamera()
    if (/^https?:\/\//i.test(data)) {
      // A label encodes a full resolve URL. Only ever navigate to a same-origin
      // URL — never follow an arbitrary external URL a hostile QR might carry
      // (open-redirect / phishing). A foreign URL just returns to the scanner.
      this.#visit(this.#sameOriginUrl(data) || this.resolveUrlValue)
    } else {
      // A bare token (manual entry or a token-only QR) → the resolve route.
      this.#visit(`${this.resolveUrlValue}/${encodeURIComponent(data)}`)
    }
  }

  // Returns the absolute, origin-checked href — never a bare path. A payload like
  // `https://<host>//evil.example/x` parses to our origin but a protocol-relative
  // pathname, so returning `pathname` would still navigate off-origin; `url.href`
  // keeps the host pinned to ours.
  #sameOriginUrl(data) {
    try {
      const url = new URL(data)
      if (url.origin === window.location.origin) return url.href
    } catch (_error) {
      // Not a parseable URL — fall through.
    }
    return null
  }

  #revealFallback() {
    this.element.classList.add("camera-unavailable")
    if (this.hasFallbackTarget) this.fallbackTarget.classList.remove("hidden")
  }

  #visit(url) {
    if (window.Turbo) window.Turbo.visit(url)
    else window.location.assign(url)
  }
}

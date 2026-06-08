import { Controller } from "@hotwired/stimulus"
import jsQR from "jsqr"

// E2 — drives the live QR scanner. Opens the rear camera, decodes frames with
// jsQR, and navigates to the resolved token. A printed label's QR encodes the
// full resolve URL, so a camera hit navigates straight there; manual entry takes
// just the token and is appended to resolveUrlValue. If the camera is denied or
// unsupported, the manual-entry fallback is revealed instead.
export default class extends Controller {
  static values = { resolveUrl: String }
  static targets = ["video", "canvas", "manual", "fallback"]

  connect() {
    this.scanning = false
    this.#startCamera()
  }

  disconnect() {
    this.#stopCamera()
  }

  // Manual code entry (camera-independent fallback).
  submitManual(event) {
    event.preventDefault()
    const token = this.manualTarget.value.trim()
    if (token) this.#visit(`${this.resolveUrlValue}/${encodeURIComponent(token)}`)
  }

  async #startCamera() {
    if (!navigator.mediaDevices?.getUserMedia) return this.#revealFallback()
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" }
      })
      this.videoTarget.srcObject = this.stream
      this.videoTarget.setAttribute("playsinline", true)
      await this.videoTarget.play()
      this.scanning = true
      this.#tick()
    } catch (_error) {
      this.#revealFallback()
    }
  }

  #stopCamera() {
    this.scanning = false
    if (this.rafId) cancelAnimationFrame(this.rafId)
    this.stream?.getTracks().forEach((track) => track.stop())
  }

  #tick() {
    if (!this.scanning) return
    const video = this.videoTarget
    if (video.readyState === video.HAVE_ENOUGH_DATA) {
      const canvas = this.canvasTarget
      canvas.width = video.videoWidth
      canvas.height = video.videoHeight
      const ctx = canvas.getContext("2d", { willReadFrequently: true })
      ctx.drawImage(video, 0, 0, canvas.width, canvas.height)
      const image = ctx.getImageData(0, 0, canvas.width, canvas.height)
      const code = jsQR(image.data, image.width, image.height)
      if (code?.data) return this.#onDecode(code.data)
    }
    this.rafId = requestAnimationFrame(() => this.#tick())
  }

  #onDecode(data) {
    this.#stopCamera()
    // The label encodes a full resolve URL; a bare token is appended instead.
    if (/^https?:\/\//i.test(data)) this.#visit(data)
    else this.#visit(`${this.resolveUrlValue}/${encodeURIComponent(data)}`)
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

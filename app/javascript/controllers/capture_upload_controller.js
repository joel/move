import { Controller } from "@hotwired/stimulus"

// Downscale a captured photo in the browser BEFORE it uploads (#547).
//
// After the async-ingest work (#545) the capture server request is ~200ms; the
// remaining latency is the phone pushing a 3–8 MB full-resolution photo over the
// (often cellular) network. Resizing to a <=2048px JPEG here cuts that upload
// ~10x, which is the whole felt wait.
//
// This is a pure speed optimization — the server's ImageNormalizer stays the
// authority (re-sniffs the bytes, strips EXIF/GPS, caps size, transcodes). So if
// anything goes wrong (an undecodable HEIC, a missing browser API, an already-
// small image) we simply upload the original and let the server handle it;
// capture must never break because the optimization failed.
// A 2x1 JPEG tagged EXIF Orientation=6: decodes to 1x2 (height > width) ONLY on
// browsers that honor `imageOrientation: "from-image"` (Chrome 79+, Safari 16+).
// We use it to feature-detect that support before downscaling — see below.
const ORIENTATION_PROBE =
  "/9j/4QAiRXhpZgAATU0AKgAAAAgAAQESAAMAAAABAAYAAAAAAAD/2wCEAAEBAQEBAQEBAQEBAQEBAQ" +
  "EBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEB" +
  "AQEBAQEBAQH/wAARCAABAAIDAREAAhEBAxEB/8QAFAABAAAAAAAAAAAAAAAAAAAAAv/EABQQAQAAAA" +
  "AAAAAAAAAAAAAAAAD/xAAUAQEAAAAAAAAAAAAAAAAAAAAA/8QAFBEBAAAAAAAAAAAAAAAAAAAAAP/a" +
  "AAwDAQACEQMRAD8AfwD/2Q=="

export default class extends Controller {
  static targets = ["file"]
  static values = { maxEdge: { type: Number, default: 2048 }, quality: { type: Number, default: 0.85 } }

  // change -> capture-upload#submit
  async submit() {
    const input = this.fileTarget
    const selected = input.files && input.files[0]
    if (!selected) return

    let downscaled = null
    try {
      downscaled = await this.downscale(selected)
    } catch {
      // Fall through and upload the original — the server normalizes it anyway.
    }

    // The user may have retaken/re-picked while we were resizing (a slow phone
    // can resolve the old resize after a newer selection). That later change
    // event owns the newer file — bail so we neither upload a stale photo nor
    // submit twice.
    if (input.files[0] !== selected) return

    if (downscaled) this.replaceFile(input, downscaled)
    this.element.requestSubmit()
  }

  // Returns a downscaled JPEG File, or null to signal "upload the original as-is".
  async downscale(file) {
    if (typeof createImageBitmap !== "function") return null
    // Only proceed where the browser applies EXIF orientation on decode. Canvas
    // strips EXIF, so on a browser that ignores imageOrientation (iOS Safari
    // <16, older Chromium) we'd re-encode a portrait phone photo sideways with
    // no EXIF left for the server to autorotate from — so there we skip and
    // upload the original (correct, just not optimized).
    if (!(await this.orientationSupported())) return null

    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const longEdge = Math.max(bitmap.width, bitmap.height)
    const scale = Math.min(1, this.maxEdgeValue / longEdge)

    // Already small and already JPEG — no point re-encoding; upload the original.
    if (scale === 1 && file.type === "image/jpeg") {
      bitmap.close?.()
      return null
    }

    const width = Math.round(bitmap.width * scale)
    const height = Math.round(bitmap.height * scale)
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext("2d")
    // JPEG has no alpha; a transparent PNG/WebP would otherwise composite onto
    // canvas' transparent-black default. Flatten onto WHITE to match the server's
    // ImageNormalizer (jpegsave flatten) so a cutout/screenshot looks identical
    // whether it took this path or the original-upload fallback.
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, width, height)
    context.drawImage(bitmap, 0, 0, width, height)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", this.qualityValue))
    // Never make it worse: a small flat PNG/WebP can re-encode to a LARGER JPEG.
    // If the result isn't actually smaller, upload the original (the whole point
    // is a smaller upload — the server normalizes either way).
    if (!blob || blob.size >= file.size) return null

    const name = `${(file.name || "capture").replace(/\.[^.]+$/, "")}.jpg`
    return new File([blob], name, { type: "image/jpeg" })
  }

  // Memoized feature-detect: does createImageBitmap honor imageOrientation?
  // Decodes the orientation-6 probe; it comes back taller-than-wide iff honored.
  // Any failure resolves false (skip the optimization, upload the original).
  orientationSupported() {
    this._orientationSupported ||= (async () => {
      try {
        const bytes = Uint8Array.from(atob(ORIENTATION_PROBE), (c) => c.charCodeAt(0))
        const probe = await createImageBitmap(new Blob([bytes], { type: "image/jpeg" }), {
          imageOrientation: "from-image"
        })
        const honored = probe.height > probe.width
        probe.close?.()
        return honored
      } catch {
        return false
      }
    })()
    return this._orientationSupported
  }

  // Swap the input's selected file for the downscaled one. Assigning input.files
  // does not fire another `change`, so this can't re-enter submit().
  replaceFile(input, file) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    input.files = transfer.files
  }
}

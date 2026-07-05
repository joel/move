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
export default class extends Controller {
  static targets = ["file"]
  static values = { maxEdge: { type: Number, default: 2048 }, quality: { type: Number, default: 0.85 } }

  // change -> capture-upload#submit
  async submit() {
    const input = this.fileTarget
    if (!input.files || input.files.length === 0) return

    try {
      const downscaled = await this.downscale(input.files[0])
      if (downscaled) this.replaceFile(input, downscaled)
    } catch {
      // Fall through and upload the original — the server normalizes it anyway.
    }
    this.element.requestSubmit()
  }

  // Returns a downscaled JPEG File, or null to signal "upload the original as-is".
  async downscale(file) {
    if (typeof createImageBitmap !== "function") return null

    // imageOrientation: bake the EXIF rotation into the pixels. Canvas discards
    // EXIF, so without this a portrait phone photo would upload sideways.
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

  // Swap the input's selected file for the downscaled one. Assigning input.files
  // does not fire another `change`, so this can't re-enter submit().
  replaceFile(input, file) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    input.files = transfer.files
  }
}

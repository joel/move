import { Controller } from "@hotwired/stimulus"

// Downscale a captured photo in the browser BEFORE it uploads (#547 / #549).
//
// After async ingest (#545) the capture server request is ~200ms; the remaining
// latency is the phone pushing a 3–8 MB full-resolution photo over the (often
// cellular) network. Resizing to a <=2048px JPEG here cuts that upload ~10x.
//
// Orientation is handled by the BROWSER, not by us: we decode with
// `imageOrientation: "from-image"`, which returns the already-display-oriented
// bitmap (verified in Chrome across all EXIF orientations), then just resize it —
// no manual EXIF parse or canvas rotation (that path was un-testable and produced
// repeated sideways-image bugs in #548). Browsers that don't honor `from-image`
// (iOS Safari <16, older Chromium) are detected up front and skipped, so a
// portrait photo is never re-encoded sideways there — it uploads as-is and the
// server autorotates it (ImageNormalizer#autorot). Because the browser decodes +
// orients, this covers JPEG, HEIC/HEIF (iPhone default, on Safari), PNG and WebP
// alike; a format the browser can't decode throws and falls back to the original.
//
// Pure speed optimization: the server's ImageNormalizer stays the authority
// (re-sniff, EXIF/GPS strip, size cap, transcode). Any failure uploads the
// original, so capture can never break because the optimization failed.
export default class extends Controller {
  static targets = ["file"]
  static values = {
    maxEdge: { type: Number, default: 2048 },
    quality: { type: Number, default: 0.85 },
    timeout: { type: Number, default: 2500 }
  }

  // change -> capture-upload#submit
  async submit() {
    const input = this.fileTarget
    const selected = input.files && input.files[0]
    if (!selected) return

    let downscaled = null
    try {
      // The optimization must NEVER block the upload. Some browsers (observed:
      // iOS decoding HEIC) can leave createImageBitmap pending forever; without
      // a bound, submit() would never reach requestSubmit() and the capture
      // would silently never send (#558). Race the resize against a timeout and,
      // whether it hangs OR throws, fall back to uploading the original.
      downscaled = await Promise.race([
        this.downscale(selected),
        new Promise((resolve) => setTimeout(() => resolve(null), this.timeoutValue))
      ])
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

  // Returns a downscaled, correctly-oriented JPEG File, or null → "upload the
  // original as-is".
  async downscale(file) {
    if (typeof createImageBitmap !== "function") return null
    if (!(await this.orientationSupported())) return null

    // from-image: the browser applies EXIF orientation on decode, so `bitmap` is
    // already in display orientation and we just resize it. Throws for a format
    // the browser can't decode (e.g. HEIC on Chrome) → caught by submit()'s
    // try/catch → original upload.
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const scale = Math.min(1, this.maxEdgeValue / Math.max(bitmap.width, bitmap.height))
    if (scale === 1) {
      bitmap.close?.() // already within the target — upload the original
      return null
    }

    const width = Math.round(bitmap.width * scale)
    const height = Math.round(bitmap.height * scale)
    const canvas = document.createElement("canvas")
    canvas.width = width
    canvas.height = height
    const context = canvas.getContext("2d")
    // Flatten transparency onto WHITE to match the server's ImageNormalizer
    // (JPEG has no alpha; the canvas default is transparent-black).
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, width, height)
    context.drawImage(bitmap, 0, 0, width, height)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", this.qualityValue))
    // Never make it worse: a re-encode can occasionally grow a small image.
    if (!blob || blob.size >= file.size) return null

    const name = `${(file.name || "capture").replace(/\.[^.]+$/, "")}.jpg`
    return new File([blob], name, { type: "image/jpeg" })
  }

  // Memoized: does this browser honor `imageOrientation: "from-image"` (Chrome
  // 79+, Safari 16+)? Where it doesn't, decoding then re-encoding would strip
  // EXIF and upload rotated photos sideways — so we skip the optimization there.
  // The probe is built at RUNTIME (no embedded binary to get malformed): a 2x1
  // JPEG tagged EXIF orientation 6 decodes to 1x2 (height > width) iff honored.
  orientationSupported() {
    this._orientationSupported ||= (async () => {
      try {
        const raw = await this.encodeProbe()
        const probe = new Blob([this.tagOrientation(raw, 6)], { type: "image/jpeg" })
        const bitmap = await createImageBitmap(probe, { imageOrientation: "from-image" })
        const honored = bitmap.height > bitmap.width
        bitmap.close?.()
        return honored
      } catch {
        return false
      }
    })()
    return this._orientationSupported
  }

  // A 2x1 JPEG's bytes, encoded by the browser (guaranteed decodable).
  async encodeProbe() {
    const canvas = document.createElement("canvas")
    canvas.width = 2
    canvas.height = 1
    canvas.getContext("2d").fillRect(0, 0, 2, 1)
    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", 1))
    return new Uint8Array(await blob.arrayBuffer())
  }

  // Splice an EXIF APP1 (big-endian TIFF, one Orientation entry) in after the SOI.
  tagOrientation(bytes, orientation) {
    const app1 = [
      // APP1 marker, then length 0x22 = 34: counted from the length field to the
      // segment end = length(2) + "Exif\0\0"(6) + TIFF header(8) + IFD(18).
      0xff, 0xe1, 0x00, 0x22,
      0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
      0x4d, 0x4d, 0x00, 0x2a, 0x00, 0x00, 0x00, 0x08, // "MM" (big-endian), magic, IFD offset 8
      0x00, 0x01, // IFD: 1 entry
      0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, orientation, 0x00, 0x00, // Orientation = SHORT
      0x00, 0x00, 0x00, 0x00 // next-IFD offset = 0 (terminates the IFD — required by the TIFF spec)
    ]
    const out = new Uint8Array(2 + app1.length + bytes.length - 2)
    out.set(bytes.slice(0, 2), 0)
    out.set(app1, 2)
    out.set(bytes.slice(2), 2 + app1.length)
    return out
  }

  // Swap the input's selected file for the downscaled one. Assigning input.files
  // does not fire another `change`, so this can't re-enter submit().
  replaceFile(input, file) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    input.files = transfer.files
  }
}

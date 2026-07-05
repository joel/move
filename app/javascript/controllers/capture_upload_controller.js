import { Controller } from "@hotwired/stimulus"

// Downscale a captured photo in the browser BEFORE it uploads (#547 / #549).
//
// After async ingest (#545) the capture server request is ~200ms; the remaining
// latency is the phone pushing a 3–8 MB full-resolution photo over the (often
// cellular) network. Resizing to a <=2048px JPEG here cuts that upload ~10x.
//
// Two decode paths, picked by a runtime feature-detect:
//
//   1. from-image (Chrome/Chromium, Safari 16+ desktop): `createImageBitmap` with
//      `imageOrientation:"from-image"` returns the already-display-oriented bitmap,
//      so we just resize it — no manual orientation. Verified in Chrome across all
//      EXIF orientations.
//   2. RAW + re-tag (iOS WebKit, where from-image is IGNORED — #549): decode the
//      raw pixels, resize WITHOUT rotating, and re-attach the file's original EXIF
//      orientation so the server autorotate + display apply it exactly as they do
//      for the untouched original. Correct by construction: a smaller image
//      carrying the same orientation metadata. A dimension self-check (decoded
//      dims vs the JPEG's stored SOF dims) confirms we actually got raw pixels
//      before re-tagging, so a browser that unexpectedly orients can't double-
//      apply and upload sideways. Scoped to JPEG and orientations {1,6,8} — the
//      cases the self-check can verify; everything else uploads the original.
//
// Pure speed optimization: the server's ImageNormalizer stays the authority
// (re-sniff, EXIF/GPS strip, size cap, transcode). Any failure — or a hang, via
// submit()'s timeout — uploads the original, so capture can never break.
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

  // Returns a downscaled JPEG File, or null → "upload the original as-is".
  async downscale(file) {
    if (typeof createImageBitmap !== "function") return null

    if (await this.orientationSupported()) {
      // Browser orients on decode — resize the display-ready bitmap. Covers JPEG,
      // HEIC/HEIF (Safari), PNG, WebP; an undecodable format throws → original.
      const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
      return this.resizeToJpeg(bitmap, file, null)
    }

    // WebKit fallback: the browser won't orient, so re-tag the raw pixels.
    return this.downscaleRawJpeg(file)
  }

  // iOS WebKit path: decode raw pixels, resize, re-attach EXIF orientation.
  async downscaleRawJpeg(file) {
    // EXIF read + re-tag are JPEG-specific; HEIC/others upload as-is (the server
    // transcodes + autorotates them).
    if (file.type !== "image/jpeg") return null

    const orientation = await this.readOrientation(file)
    // Only the orientations the dimension self-check below can verify: 1 (upright,
    // no rotation) and the two 90° rotations (6/8, dims swap). Mirrored/180
    // orientations aren't dim-distinguishable, so they upload the original.
    if (![1, 6, 8].includes(orientation)) return null

    const raw = await this.readRawDimensions(file)
    if (!raw) return null

    const bitmap = await createImageBitmap(file)
    // Did the browser already orient? A 90° rotation swaps the dimensions, so if
    // the decoded bitmap still matches the file's stored (raw) dims we truly got
    // raw pixels and must re-tag; if it's swapped, the browser oriented it and
    // re-tagging would double-apply — so don't.
    const gotRaw = bitmap.width === raw.width && bitmap.height === raw.height
    return this.resizeToJpeg(bitmap, file, gotRaw ? orientation : null)
  }

  // Resize a decoded bitmap to <=maxEdge and encode JPEG. `reinjectOrientation`
  // (when not 1/null) splices the EXIF Orientation back in so downstream rotates
  // the resized raw pixels. Consumes (closes) the bitmap. Null if not worth it.
  async resizeToJpeg(bitmap, file, reinjectOrientation) {
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
    if (!blob) return null

    let bytes = new Uint8Array(await blob.arrayBuffer())
    if (reinjectOrientation && reinjectOrientation !== 1) bytes = this.tagOrientation(bytes, reinjectOrientation)
    // Never make it worse: a re-encode can occasionally grow a small image.
    if (bytes.byteLength >= file.size) return null

    const name = `${(file.name || "capture").replace(/\.[^.]+$/, "")}.jpg`
    return new File([bytes], name, { type: "image/jpeg" })
  }

  // Memoized: does this browser honor `imageOrientation: "from-image"` (Chrome
  // 79+, Safari 16+ desktop)? iOS WebKit ignores it (→ the raw path above). The
  // probe is built at RUNTIME (no embedded binary to get malformed): a 2x1 JPEG
  // tagged EXIF orientation 6 decodes to 1x2 (height > width) iff honored.
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

  // Read the EXIF Orientation tag (1–8) from a JPEG's APP1 segment, or 1 if it's
  // absent/unreadable. Only the first APP1 (where Exif lives) is inspected.
  async readOrientation(file) {
    try {
      const view = new DataView(await file.slice(0, 131072).arrayBuffer())
      if (view.byteLength < 4 || view.getUint16(0) !== 0xffd8) return 1 // not a JPEG (SOI)

      let offset = 2
      while (offset + 4 <= view.byteLength) {
        const marker = view.getUint16(offset)
        if (marker === 0xffe1 && view.getUint32(offset + 4) === 0x45786966) { // "Exif"
          const tiff = offset + 10
          const little = view.getUint16(tiff) === 0x4949 // "II" little-endian, else "MM" big
          const ifd = tiff + view.getUint32(tiff + 4, little)
          const entries = view.getUint16(ifd, little)
          for (let i = 0; i < entries; i++) {
            const entry = ifd + 2 + i * 12
            if (view.getUint16(entry, little) === 0x0112) {
              const value = view.getUint16(entry + 8, little)
              return value >= 1 && value <= 8 ? value : 1
            }
          }
          return 1
        }
        if ((marker & 0xff00) !== 0xff00) return 1 // not a valid marker — give up
        offset += 2 + view.getUint16(offset + 2) // skip this segment
      }
      return 1
    } catch {
      return 1
    }
  }

  // Read the raw (as-stored, pre-orientation) pixel dimensions from a JPEG's
  // Start-Of-Frame marker, or null if unreadable. Used to detect whether the
  // decoder already applied EXIF orientation (a 90° rotation swaps these).
  async readRawDimensions(file) {
    try {
      const view = new DataView(await file.slice(0, 131072).arrayBuffer())
      if (view.getUint16(0) !== 0xffd8) return null // not a JPEG (SOI)

      let offset = 2
      while (offset + 9 < view.byteLength) {
        if (view.getUint8(offset) !== 0xff) return null
        const marker = view.getUint8(offset + 1)
        // SOF0..SOF15 carry frame dimensions, except the non-SOF markers that
        // share the 0xC_ range: DHT (C4), JPG (C8), DAC (CC).
        if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
          return { height: view.getUint16(offset + 5), width: view.getUint16(offset + 7) }
        }
        offset += 2 + view.getUint16(offset + 2) // skip this segment by its length
      }
      return null
    } catch {
      return null
    }
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

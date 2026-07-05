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
// anything goes wrong (an undecodable HEIC, a missing API, an already-small
// image) we upload the original and let the server handle it; capture must never
// break because the optimization failed.
//
// EXIF orientation is applied EXPLICITLY (read from the file, baked into the
// canvas transform) rather than relying on createImageBitmap's `imageOrientation`
// option — that option is unsupported on iOS Safari <16 / older Chromium, where
// it would silently produce sideways uploads (canvas strips EXIF, so the server
// can't autorotate afterwards). Doing it ourselves is correct on every browser.
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

  // Returns a downscaled, correctly-oriented JPEG File, or null to signal
  // "upload the original as-is".
  async downscale(file) {
    if (typeof createImageBitmap !== "function") return null

    const orientation = await this.readOrientation(file)
    // `none`: we handle EXIF orientation ourselves below, so decode raw pixels
    // consistently across browsers (never double-apply).
    const bitmap = await createImageBitmap(file, { imageOrientation: "none" })
    const swap = orientation >= 5 && orientation <= 8 // 90°/270° → displayed dims are swapped
    const displayWidth = swap ? bitmap.height : bitmap.width
    const displayHeight = swap ? bitmap.width : bitmap.height

    const scale = Math.min(1, this.maxEdgeValue / Math.max(displayWidth, displayHeight))
    // Nothing to gain: already small AND already upright JPEG — upload the original.
    if (scale === 1 && orientation <= 1 && file.type === "image/jpeg") {
      bitmap.close?.()
      return null
    }

    const outWidth = Math.round(displayWidth * scale)
    const outHeight = Math.round(displayHeight * scale)
    const canvas = document.createElement("canvas")
    canvas.width = outWidth
    canvas.height = outHeight
    const context = canvas.getContext("2d")
    // Flatten transparency onto WHITE to match the server's ImageNormalizer
    // (JPEG has no alpha; the canvas default is transparent-black).
    context.fillStyle = "#ffffff"
    context.fillRect(0, 0, outWidth, outHeight)
    this.applyOrientation(context, orientation, outWidth, outHeight)
    // After the orientation transform the drawing space is in the pre-swap
    // (raw) axis, so draw scaled to the raw-oriented dimensions.
    context.drawImage(bitmap, 0, 0, swap ? outHeight : outWidth, swap ? outWidth : outHeight)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", this.qualityValue))
    // Never make it worse: a small flat PNG/WebP can re-encode to a LARGER JPEG.
    if (!blob || blob.size >= file.size) return null

    const name = `${(file.name || "capture").replace(/\.[^.]+$/, "")}.jpg`
    return new File([blob], name, { type: "image/jpeg" })
  }

  // Canonical EXIF-orientation → canvas transform (w, h are the OUTPUT dims).
  applyOrientation(context, orientation, width, height) {
    switch (orientation) {
      case 2: context.transform(-1, 0, 0, 1, width, 0); break // flip-x
      case 3: context.transform(-1, 0, 0, -1, width, height); break // 180°
      case 4: context.transform(1, 0, 0, -1, 0, height); break // flip-y
      case 5: context.transform(0, 1, 1, 0, 0, 0); break // transpose
      case 6: context.transform(0, 1, -1, 0, height, 0); break // 90° CW
      case 7: context.transform(0, -1, -1, 0, height, width); break // transverse
      case 8: context.transform(0, -1, 1, 0, 0, width); break // 270° CW
      default: break // 1 (or unknown): no transform
    }
  }

  // Read the EXIF Orientation tag (1–8) from a JPEG's APP1 segment, or 1 if it's
  // absent/unreadable (a non-JPEG, a screenshot, a stripped image). Reading only
  // the first 128 KB is enough — EXIF lives in the first APP1 marker.
  async readOrientation(file) {
    try {
      const view = new DataView(await file.slice(0, 131072).arrayBuffer())
      if (view.byteLength < 4 || view.getUint16(0) !== 0xffd8) return 1 // not a JPEG (SOI)

      let offset = 2
      while (offset + 4 <= view.byteLength) {
        const marker = view.getUint16(offset)
        if (marker === 0xffe1) {
          // APP1 — expect "Exif\0\0" then a TIFF header.
          if (view.getUint32(offset + 4) !== 0x45786966) return 1
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

  // Swap the input's selected file for the downscaled one. Assigning input.files
  // does not fire another `change`, so this can't re-enter submit().
  replaceFile(input, file) {
    const transfer = new DataTransfer()
    transfer.items.add(file)
    input.files = transfer.files
  }
}

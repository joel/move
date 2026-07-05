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
// Scope is deliberately narrow so it's correct on every browser WITHOUT relying
// on canvas rotation (which can't be verified in CI) or on createImageBitmap's
// `imageOrientation` (unsupported on iOS Safari <16 / older Chromium): only an
// UPRIGHT (EXIF orientation 1, read from the file) JPEG is resized, which needs
// no rotation. Rotated JPEGs, HEIC/HEIF (iPhone default), PNG and WebP upload
// as-is — the server transcodes + autorotates them. Optimizing those cases is a
// Phase 3b follow-up that needs real-device verification.
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
    // JPEG only. It's the one format whose orientation we can read and apply
    // reliably (EXIF, below). HEIC/HEIF (iPhone default), PNG, WebP etc. upload
    // as-is — the server's ImageNormalizer transcodes + autorotates them; a
    // client re-encode there would risk a sideways image (HEIC has orientation
    // we can't read here) with EXIF stripped. Optimizing HEIC in-browser is a
    // Phase 3b follow-up (needs real-device verification).
    if (file.type !== "image/jpeg") return null

    // Only UPRIGHT (orientation 1, or absent) JPEGs are resized here. A rotated
    // JPEG would need a canvas rotation transform, which can't be verified in
    // this repo (no browser/device in CI for canvas output); rather than risk a
    // sideways/cropped upload we send the original and let the server autorotate
    // (ImageNormalizer#autorot). Correctly resizing rotated + HEIC captures is a
    // Phase 3b follow-up with real-device verification.
    if ((await this.readOrientation(file)) !== 1) return null

    const bitmap = await createImageBitmap(file)
    const scale = Math.min(1, this.maxEdgeValue / Math.max(bitmap.width, bitmap.height))
    if (scale === 1) {
      bitmap.close?.() // already within the target — upload the original
      return null
    }

    const outWidth = Math.round(bitmap.width * scale)
    const outHeight = Math.round(bitmap.height * scale)
    const canvas = document.createElement("canvas")
    canvas.width = outWidth
    canvas.height = outHeight
    canvas.getContext("2d").drawImage(bitmap, 0, 0, outWidth, outHeight)
    bitmap.close?.()

    const blob = await new Promise((resolve) => canvas.toBlob(resolve, "image/jpeg", this.qualityValue))
    // Never make it worse (a re-encode can occasionally grow a small image).
    if (!blob || blob.size >= file.size) return null

    const name = `${(file.name || "capture").replace(/\.[^.]+$/, "")}.jpg`
    return new File([blob], name, { type: "image/jpeg" })
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
        // The Exif APP1 — but a JPEG may carry an earlier non-Exif APP1 (e.g.
        // XMP), so only parse the one whose payload starts with "Exif"; any
        // other segment is skipped by its length so scanning continues.
        if (marker === 0xffe1 && view.getUint32(offset + 4) === 0x45786966) {
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
        offset += 2 + view.getUint16(offset + 2) // skip this segment (incl. non-Exif APP1)
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

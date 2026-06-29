import { Controller } from "@hotwired/stimulus"

// Gallery lightbox. A single native <dialog> viewer shared by every grid tile.
// Each tile is a target carrying the photo's :detail src, caption and box href as
// data-*; opening reads the clicked tile, prev/next cycle (wrapping) over the
// rendered set. showModal() gives focus-trap, Escape and the ::backdrop for free;
// we add arrow-key nav and click-outside-to-close.
//
//   div(data: { controller: "lightbox" })
//     button(data: { lightbox_target: "tile", action: "click->lightbox#open", src/caption/href })
//     dialog(data: { lightbox_target: "dialog", action: "keydown->lightbox#key" })
//       img(data-lightbox-target="image"), span(caption), a(link)
export default class extends Controller {
  static targets = ["tile", "dialog", "image", "caption", "link"]

  open(event) {
    this.index = this.tileTargets.indexOf(event.currentTarget)
    if (this.index < 0) this.index = 0
    this.render()
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
    // Drop the heavy detail image so it isn't held in memory between views.
    this.imageTarget.removeAttribute("src")
  }

  next() {
    this.move(1)
  }

  prev() {
    this.move(-1)
  }

  move(step) {
    const count = this.tileTargets.length
    if (count === 0) return
    this.index = (this.index + step + count) % count
    this.render()
  }

  // Render the current tile's photo into the viewer.
  render() {
    const tile = this.tileTargets[this.index]
    if (!tile) return
    const { src, caption, href } = tile.dataset
    // Clear rather than retain the previous photo when a tile has no detail image,
    // so the viewer never shows the wrong photo under the new caption.
    if (src) this.imageTarget.src = src
    else this.imageTarget.removeAttribute("src")
    this.imageTarget.alt = caption || ""
    if (this.hasCaptionTarget) this.captionTarget.textContent = caption || ""
    if (this.hasLinkTarget && href) this.linkTarget.href = href
  }

  // Arrow keys cycle; Escape is handled natively by <dialog>.
  key(event) {
    if (event.key === "ArrowRight") {
      event.preventDefault()
      this.next()
    } else if (event.key === "ArrowLeft") {
      event.preventDefault()
      this.prev()
    }
  }

  // A click whose target is the backdrop wrapper itself (not the image or a
  // control) closes the viewer.
  backdropClose(event) {
    if (event.target === event.currentTarget) this.close()
  }
}

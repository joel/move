import { Controller } from "@hotwired/stimulus"
import PhotoSwipeLightbox from "photoswipe/lightbox"

// Gallery lightbox — a thin wrapper around vendored PhotoSwipe 5 (#598), which
// owns the hard parts: follow-finger swipe with real physics, pinch/double-tap
// zoom, neighbour preloading, keyboard nav, focus trap and a11y. Each grid tile
// is a target carrying the photo's :thumb/:detail srcs, caption and box href as
// data-*; open() builds the slide list from the rendered tiles.
//
// PhotoSwipe requires per-slide pixel dimensions up front, which the app can't
// reliably supply (blobs may be unanalyzed). Strategy: estimate from the tile's
// already-loaded grid thumb (exact aspect ratio) scaled into the :detail
// bounds, then correct to the real naturalWidth/Height once the full image
// loads (loadComplete), persisting the exact size back onto the tile for
// subsequent opens.
//
//   div(data: { controller: "lightbox", lightbox_labels_value: {…}.to_json,
//               action: "turbo:before-cache@document->lightbox#teardown" })
//     button(data: { lightbox_target: "tile", action: "click->lightbox#open",
//                    src/thumb/caption/href }) > img (grid thumb)

// MediaVariants::TransformUrl::SIZES[:detail] — the served image's bounding box.
const DETAIL_BOX = 1600

export default class extends Controller {
  static targets = ["tile"]
  static values = { labels: Object }

  connect() {
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
    this.lightbox = new PhotoSwipeLightbox({
      pswpModule: () => import("photoswipe"),
      showHideAnimationType: reducedMotion ? "none" : "zoom",
      bgOpacity: 0.85,
      wheelToZoom: true,
      counter: false, // the location caption is the context; a counter would sit under it
      arrowPrevTitle: this.labelsValue.prev,
      arrowNextTitle: this.labelsValue.next,
      closeTitle: this.labelsValue.close,
      zoomTitle: this.labelsValue.zoom,
      errorMsg: this.labelsValue.error
    })
    this.registerChrome()
    this.correctSizesOnLoad()
    this.lightbox.init()
  }

  disconnect() {
    this.teardown()
    this.lightbox?.destroy()
    this.lightbox = null
  }

  open(event) {
    if (!this.lightbox) return
    const index = this.tileTargets.indexOf(event.currentTarget)
    if (index < 0) return
    this.lightbox.options.dataSource = this.tileTargets.map((tile) => this.slideFor(tile))
    this.lightbox.loadAndOpen(index)
  }

  // turbo:before-cache — Turbo must never snapshot an open viewer (PhotoSwipe
  // appends its DOM to <body>). destroy() on an open viewer routes through
  // close(), which removes the `.pswp` root only on a 0ms timeout — but Turbo
  // clones the document synchronously right after this event, so we must strip
  // the element ourselves or a stale overlay is cached and reappears on
  // back-navigation (Codex #599).
  teardown() {
    const pswp = this.lightbox?.pswp
    if (!pswp) return
    pswp.destroy()
    pswp.element?.remove()
  }

  slideFor(tile) {
    const { src, thumb, caption, href } = tile.dataset
    const [width, height] = this.dimensionsFor(tile)
    // element: the tile anchors PhotoSwipe's zoom-from-thumbnail open/close
    // animation; caption/href/tile ride along for the custom chrome below.
    return { src, msrc: thumb, alt: caption || "", width, height, element: tile, caption, href, tile }
  }

  // Exact size once a previous view corrected it; otherwise the grid thumb's
  // natural size (its ratio is the photo's) scaled into the :detail box; a
  // square placeholder when the thumb hasn't loaded yet (lazy, off-screen).
  dimensionsFor(tile) {
    if (tile.dataset.pswpWidth) return [Number(tile.dataset.pswpWidth), Number(tile.dataset.pswpHeight)]
    const thumb = tile.querySelector("img")
    const w = thumb?.naturalWidth
    const h = thumb?.naturalHeight
    if (!w || !h) return [DETAIL_BOX, DETAIL_BOX]
    const scale = Math.min(DETAIL_BOX / w, DETAIL_BOX / h)
    return [Math.round(w * scale), Math.round(h * scale)]
  }

  // The served image is authoritative: replace the estimate with its real
  // pixel size (re-rendering the slide when they differ) and persist it on the
  // tile so the next open needs no correction.
  correctSizesOnLoad() {
    this.lightbox.on("loadComplete", ({ content }) => {
      const data = content.data
      const img = content.element
      if (!img?.naturalWidth) return
      data.tile?.setAttribute("data-pswp-width", img.naturalWidth)
      data.tile?.setAttribute("data-pswp-height", img.naturalHeight)
      if (data.width === img.naturalWidth && data.height === img.naturalHeight) return
      data.width = img.naturalWidth
      data.height = img.naturalHeight
      content.slide?.pswp?.refreshSlideContent(content.slide.index)
    })
  }

  // Custom chrome: the location caption (top-left) and the "view box" link
  // (top-right, before the close button) — both follow the current slide.
  registerChrome() {
    this.lightbox.on("uiRegister", () => {
      const pswp = this.lightbox.pswp
      // Read the slide by index, not `pswp.currSlide` — during a `change` the
      // current slide can momentarily be a placeholder whose `.data` isn't
      // populated yet, which would blank the caption/link mid-turn.
      const dataFor = () => pswp.options.dataSource?.[pswp.currIndex] || {}

      pswp.ui.registerElement({
        name: "move-caption",
        appendTo: "root",
        onInit: (el) => {
          const update = () => { el.textContent = dataFor().caption || "" }
          pswp.on("change", update)
          update()
        }
      })

      pswp.ui.registerElement({
        name: "move-view-box",
        tagName: "a",
        isButton: true,
        appendTo: "root",
        html: this.labelsValue.viewBox,
        onInit: (el) => {
          const update = () => {
            const href = dataFor().href
            if (href) el.setAttribute("href", href)
          }
          pswp.on("change", update)
          update()
        }
      })
    })
  }
}

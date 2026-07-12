import PhotoSwipeLightbox from "photoswipe/lightbox"

// Desktop gallery viewer — the PhotoSwipe 5 integration (#598/#599), extracted
// verbatim from lightbox_controller.js into a strategy the controller lazily
// imports on fine-pointer devices (#604). Touch devices get thumbs_viewer.js
// instead and never download this module (or PhotoSwipe). PhotoSwipe owns the
// hard parts: follow-finger swipe with real physics, pinch/double-tap zoom,
// neighbour preloading, keyboard nav, focus trap and a11y.
//
// PhotoSwipe requires per-slide pixel dimensions up front, which the app can't
// reliably supply (blobs may be unanalyzed). Strategy: estimate from the tile's
// already-loaded grid thumb (exact aspect ratio) scaled into the :detail
// bounds, then correct to the real naturalWidth/Height once the full image
// loads (loadComplete), persisting the exact size back onto the tile for
// subsequent opens.

// MediaVariants::TransformUrl::SIZES[:detail] — the served image's bounding box.
const DETAIL_BOX = 1600

export class PhotoSwipeViewer {
  constructor(labels) {
    this.labels = labels
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
    this.lightbox = new PhotoSwipeLightbox({
      pswpModule: () => import("photoswipe"),
      showHideAnimationType: reducedMotion ? "none" : "zoom",
      bgOpacity: 0.85,
      wheelToZoom: true,
      counter: false, // the location caption is the context; a counter would sit under it
      arrowPrevTitle: labels.prev,
      arrowNextTitle: labels.next,
      closeTitle: labels.close,
      zoomTitle: labels.zoom,
      errorMsg: labels.error
    })
    this.seedThumbPlaceholders()
    this.registerChrome()
    this.correctSizesOnLoad()
    this.lightbox.init()
  }

  // slides: [{ src, thumb, caption, href, tile }] built by the controller.
  open(slides, index) {
    if (!this.lightbox) return
    // Align `loop` with PhotoSwipe's own `canLoop()` (which requires > 2 items):
    // otherwise a 2-photo gallery keeps `loop: true`, so the end arrows never get
    // the disabled treatment (that branch is gated on `!options.loop`) yet
    // navigation can't wrap — leaving enabled-but-dead arrows. With loop off for
    // ≤ 2 photos the arrows disable cleanly at the ends (Codex #599).
    this.lightbox.options.loop = slides.length > 2
    this.lightbox.options.dataSource = slides.map((slide) => this.slideFor(slide))
    this.lightbox.loadAndOpen(index)
  }

  slideFor(slide) {
    const [width, height] = this.dimensionsFor(slide.tile)
    // element: the tile anchors PhotoSwipe's zoom-from-thumbnail open/close
    // animation; caption/href/tile ride along for the custom chrome below.
    return {
      src: slide.src,
      msrc: slide.thumb,
      alt: slide.caption || "",
      width,
      height,
      element: slide.tile,
      caption: slide.caption,
      href: slide.href,
      tile: slide.tile
    }
  }

  // Show each slide's grid thumb as its placeholder while :detail loads.
  // PhotoSwipe's default only does this for the first-opened slide
  // (isFirstSlide), so without this filter, swiping/clicking to an as-yet-
  // unloaded slide flashes a blank frame until the full image arrives — undoing
  // the thumb-first feedback for the very navigation case this viewer targets.
  seedThumbPlaceholders() {
    this.lightbox.addFilter("placeholderSrc", (placeholderSrc, content) =>
      content?.data?.msrc || placeholderSrc)
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
        html: this.labels.viewBox,
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

  // turbo:before-cache — Turbo must never snapshot an open viewer (PhotoSwipe
  // appends its DOM to <body>), and clones the document synchronously right
  // after this event. `destroy()` fully tears down a fully-open viewer, but if
  // it fires during the OPEN animation its close() bails (opener not yet open),
  // so it neither removes the `.pswp` root nor its global listeners. Do both
  // ourselves — strip the element so no stale overlay is cached, and remove the
  // listeners so nothing lingers into the next page (Codex #599). Both are
  // no-ops when destroy() already handled them. Idempotent: safe to call from
  // both turbo:before-cache and disconnect.
  destroy() {
    const pswp = this.lightbox?.pswp
    if (pswp) {
      pswp.destroy()
      pswp.element?.remove()
      pswp.events?.removeAll?.()
      // PhotoSwipe sets `window.pswp` on open and clears it only in its own
      // destroy-event handler — which the mid-open bail skips. A stale global
      // makes loadAndOpen() short-circuit (`if (window.pswp) return`), so the
      // viewer would never open again after this race until a full reload. Clear
      // the global we know points at this instance (Codex #599).
      if (window.pswp === pswp) delete window.pswp
    }
    this.lightbox?.destroy()
    this.lightbox = null
  }
}

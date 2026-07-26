import { Controller } from "@hotwired/stimulus"

// Gallery lightbox dispatcher (#598/#599/#604). Each grid tile is a target
// carrying the photo's :thumb/:detail srcs, caption and box href as data-*.
// Tapping a tile opens a fullscreen viewer — but WHICH viewer depends on the
// device:
//
//   • fine pointer (desktop/laptop) → PhotoSwipe (lightbox/photoswipe_viewer),
//     the zoom-from-thumbnail lightbox with wheel-zoom and arrow keys.
//   • coarse pointer (touch/mobile)  → a Swiper thumbs-gallery
//     (lightbox/thumbs_viewer): a swipeable main image with a bottom thumb strip.
//
// The viewer module is imported lazily on first open, so a phone never downloads
// PhotoSwipe and a desktop never downloads Swiper. Both viewers append their DOM
// to <body> (outside Turbo's cached snapshot), so teardown() strips them on
// turbo:before-cache.
//
//   div(data: { controller: "lightbox", lightbox_labels_value: {…}.to_json,
//               action: "turbo:before-cache@document->lightbox#teardown" })
//     button(data: { lightbox_target: "tile", action: "click->lightbox#open",
//                    src/thumb/caption/href }) > img (grid thumb)

export default class extends Controller {
  static targets = ["tile"]
  static values = { labels: Object }

  connect() {
    this.viewer = null
    this.viewerPromise = null
    // Warm the desktop viewer at connect (as the pre-#604 controller did, so the
    // first open is instant). The touch thumbs-gallery is left lazy — its Swiper
    // bundle is only fetched when a photo is actually opened.
    if (!this.prefersThumbs()) this.buildViewer()
  }

  disconnect() {
    this.teardown()
  }

  // turbo:before-cache — Turbo must never snapshot an open viewer.
  teardown() {
    this.viewer?.destroy()
    this.viewer = null
    this.viewerPromise = null
  }

  async open(event) {
    const index = this.tileTargets.indexOf(event.currentTarget)
    if (index < 0) return
    const viewer = await this.buildViewer()
    // A turbo:before-cache during the async import can tear us down mid-open;
    // bail if we were torn down (buildViewer resolves to null then).
    if (!viewer || viewer !== this.viewer) return
    viewer.open(this.slides(), index)
  }

  // Lazily import + construct the device-appropriate viewer, memoizing the
  // in-flight promise so concurrent opens share one construction.
  buildViewer() {
    if (this.viewer) return Promise.resolve(this.viewer)
    if (!this.viewerPromise) {
      // Capture the promise so the resolver can prove it's still the current
      // one: a teardown (viewerPromise → null) or a teardown-then-reopen
      // (viewerPromise → a new promise) mid-import must NOT construct a stray,
      // never-destroyed viewer.
      const promise = this.importViewer().then((Viewer) => {
        if (this.viewerPromise !== promise) return null
        this.viewer = new Viewer(this.labelsValue)
        return this.viewer
      })
      this.viewerPromise = promise
    }
    return this.viewerPromise
  }

  async importViewer() {
    if (this.prefersThumbs()) {
      const { ThumbsViewer } = await import("lightbox/thumbs_viewer")
      return ThumbsViewer
    }
    const { PhotoSwipeViewer } = await import("lightbox/photoswipe_viewer")
    return PhotoSwipeViewer
  }

  // Touch / coarse-pointer devices get the thumbs-gallery. A `?viewer=thumbs` /
  // `?viewer=photoswipe` query param overrides the detection so either path is
  // reachable for QA and system specs on a desktop browser.
  prefersThumbs() {
    const forced = new URLSearchParams(window.location.search).get("viewer")
    if (forced === "thumbs") return true
    if (forced === "photoswipe") return false
    return matchMedia("(pointer: coarse)").matches
  }

  slides() {
    return this.tileTargets.map((tile) => {
      const { src, thumb, caption, href } = tile.dataset
      return { src, thumb, caption: caption || "", href, items: this.itemsFor(tile), tile }
    })
  }

  // data-items is server-minted JSON [{name, url}] — the photo's items with
  // their seeded-search URLs (#724). Anything malformed degrades to "no chips"
  // rather than breaking the open.
  itemsFor(tile) {
    try {
      const parsed = JSON.parse(tile.dataset.items || "[]")
      if (!Array.isArray(parsed)) return []
      return parsed.filter((item) => typeof item?.name === "string" && typeof item?.url === "string")
    } catch {
      return []
    }
  }
}

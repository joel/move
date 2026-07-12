import { Controller } from "@hotwired/stimulus"

// Gallery lightbox dispatcher (#598/#599/#604). Each grid tile is a target
// carrying the photo's :thumb/:detail srcs, caption and box href as data-*.
// Tapping a tile opens a fullscreen viewer — but WHICH viewer depends on the
// device:
//
//   • fine pointer (desktop/laptop) → PhotoSwipe (lightbox/photoswipe_viewer),
//     the zoom-from-thumbnail lightbox with wheel-zoom and arrow keys.
//   • coarse pointer (touch/mobile)  → a Swiper "effect-cards" deck
//     (lightbox/card_deck_viewer) you flick through one-handed.
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
    // first open is instant). The touch deck is left lazy — its Swiper bundle is
    // only fetched when a photo is actually opened.
    if (!this.prefersDeck()) this.buildViewer()
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
    this.viewerPromise ||= this.importViewer().then((Viewer) => {
      // Torn down while the module was loading — don't construct a stray viewer.
      if (this.viewerPromise === null) return null
      this.viewer = new Viewer(this.labelsValue)
      return this.viewer
    })
    return this.viewerPromise
  }

  async importViewer() {
    if (this.prefersDeck()) {
      const { CardDeckViewer } = await import("lightbox/card_deck_viewer")
      return CardDeckViewer
    }
    const { PhotoSwipeViewer } = await import("lightbox/photoswipe_viewer")
    return PhotoSwipeViewer
  }

  // Touch / coarse-pointer devices get the card deck. A `?viewer=deck` /
  // `?viewer=photoswipe` query param overrides the detection so either path is
  // reachable for QA and system specs on a desktop browser.
  prefersDeck() {
    const forced = new URLSearchParams(window.location.search).get("viewer")
    if (forced === "deck") return true
    if (forced === "photoswipe") return false
    return matchMedia("(pointer: coarse)").matches
  }

  slides() {
    return this.tileTargets.map((tile) => {
      const { src, thumb, caption, href } = tile.dataset
      return { src, thumb, caption: caption || "", href, tile }
    })
  }
}

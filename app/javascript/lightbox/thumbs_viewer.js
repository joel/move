import Swiper from "swiper"
import { Thumbs, FreeMode, Zoom, Keyboard, A11y } from "swiper"

// Mobile gallery viewer (#604) — a fullscreen thumbs-gallery
// (https://swiperjs.com/demos#thumbs-gallery). On touch / coarse-pointer devices
// the lightbox controller lazily imports this instead of PhotoSwipe, so a phone
// never downloads the desktop viewer (and desktop never downloads Swiper).
//
// A big main image you swipe through, with a bottom thumbnail strip to jump
// across the set (a Move gallery can hold hundreds of photos — a strip beats
// swiping one-by-one). Two synced Swipers: the main (pinch/double-tap zoom via
// the Zoom module — parity with PhotoSwipe) and the thumbs (free-scrolling).
// This class owns the app shell: a fullscreen overlay appended to <body>, the
// caption / counter / "view box" link / close chrome that follows the active
// image, keyboard + a11y, a focus trap, ESC / backdrop close, body-scroll lock
// and reduced-motion fallback. Like PhotoSwipe it lives outside the Turbo-cached
// DOM, so the controller tears it down on turbo:before-cache.
//
// slides: [{ src, thumb, caption, href, tile }] built by the controller from the
// grid tiles — src is the :detail image, thumb the already-loaded grid thumb.

// How near the active image a :detail source is hydrated; the rest stay deferred
// (thumbnails are the already-loaded grid thumbs, so they all load cheaply).
const EAGER_RADIUS = 1

export class ThumbsViewer {
  constructor(labels) {
    this.labels = labels
    this.overlay = null
    this.mainSwiper = null
    this.thumbsSwiper = null
    this.slides = []
    this.pendingIndex = 0
    this.lastFocus = null
    this.previousBodyOverflow = ""
    this.onKeydown = this.onKeydown.bind(this)
  }

  open(slides, index) {
    // Re-entrant safety: a second open() (e.g. rapid taps) rebuilds cleanly
    // rather than stacking overlays.
    if (this.overlay) this.destroy()
    this.slides = slides
    // Stashed before buildOverlay so buildMainSlide (which runs before the
    // Swipers) can decide which :detail sources to hydrate against the opened
    // index.
    this.pendingIndex = index
    this.lastFocus = document.activeElement
    this.overlay = this.buildOverlay(slides)
    document.body.appendChild(this.overlay)
    this.lockScroll()
    // The main Swiper references the thumbs Swiper, so build thumbs first.
    this.thumbsSwiper = this.buildThumbsSwiper()
    this.mainSwiper = this.buildMainSwiper(index)
    this.syncChrome()
    this.hydrateNear()
    document.addEventListener("keydown", this.onKeydown)
    // Focus the close control so ESC/keyboard and the focus trap have an anchor
    // inside the dialog; guard for the rare null (element not yet laid out).
    this.closeButton?.focus()
  }

  buildOverlay(slides) {
    const overlay = el("div", {
      class: "move-gallery fixed inset-0 z-[1000] flex flex-col bg-page/95 backdrop-blur-sm",
      role: "dialog",
      "aria-modal": "true",
      "aria-label": this.labels.dialog
    })

    // Backdrop — a tap outside the image dismisses. It sits behind the chrome,
    // main image and thumbs (which come later in source and carry z-10/z-20).
    const backdrop = el("div", { class: "move-gallery__backdrop absolute inset-0", "aria-hidden": "true" })
    backdrop.addEventListener("click", () => this.close())
    overlay.appendChild(backdrop)

    overlay.appendChild(this.buildChrome())

    // Main image swiper — fills the space between chrome and thumbs.
    this.mainEl = el("div", { class: "move-gallery__main swiper relative z-10 min-h-0 w-full flex-1" })
    const mainWrapper = el("div", { class: "swiper-wrapper" })
    slides.forEach((slide, i) => mainWrapper.appendChild(this.buildMainSlide(slide, i)))
    this.mainEl.appendChild(mainWrapper)
    overlay.appendChild(this.mainEl)

    // Thumbnail strip pinned at the bottom (above the home indicator).
    this.thumbsEl = el("div", {
      class: "move-gallery__thumbs swiper relative z-10 w-full shrink-0 px-3 pt-2 " +
             "pb-[calc(env(safe-area-inset-bottom)_+_0.5rem)]"
    })
    const thumbsWrapper = el("div", { class: "swiper-wrapper" })
    slides.forEach((slide) => thumbsWrapper.appendChild(this.buildThumb(slide)))
    this.thumbsEl.appendChild(thumbsWrapper)
    overlay.appendChild(this.thumbsEl)

    return overlay
  }

  buildMainSlide(slide, i) {
    const slideEl = el("div", { class: "move-gallery__slide swiper-slide flex h-full items-center justify-center" })
    const zoom = el("div", { class: "swiper-zoom-container flex h-full w-full items-center justify-center" })
    const img = el("img", {
      class: "max-h-full max-w-full object-contain",
      alt: slide.caption || "",
      draggable: "false"
    })
    // Only the opened image and its immediate neighbours get a real `src`; the
    // rest hold their URL in data-src and are hydrated by hydrateNear() as they
    // approach the active index. A gallery can render hundreds of photos, and
    // the whole set is inserted into the DOM at once — setting every `src` here
    // would let opening ONE photo download every high-res :detail image.
    if (Math.abs(i - this.pendingIndex) <= EAGER_RADIUS) {
      img.src = slide.src
    } else {
      img.dataset.src = slide.src
    }
    // Parity with the desktop lightbox's errorMsg: if the :detail image fails
    // (e.g. an expired signed URL), show the localized error instead of a broken
    // image.
    img.addEventListener("error", () => this.markSlideFailed(zoom), { once: true })
    zoom.appendChild(img)
    slideEl.appendChild(zoom)
    return slideEl
  }

  buildThumb(slide) {
    // Thumbnails are the already-loaded grid thumbs, so they are cheap to show
    // and need no lazy handling. Swiper adds `swiper-slide-thumb-active` to the
    // active one; the opacity/ring styling lives in application.css.
    const thumb = el("div", { class: "move-gallery__thumb swiper-slide !w-16" })
    if (slide.thumb) {
      const img = el("img", {
        class: "h-16 w-16 rounded-lg object-cover",
        src: slide.thumb,
        alt: "",
        draggable: "false"
      })
      thumb.appendChild(img)
    }
    return thumb
  }

  // Give the active image and its immediate neighbours a real `src` (from
  // data-src) as they come into range, so navigating loads :detail images
  // just-in-time instead of all at once.
  hydrateNear() {
    if (!this.mainSwiper) return
    const active = this.mainSwiper.activeIndex
    this.mainSwiper.slides.forEach((slideEl, i) => {
      if (Math.abs(i - active) > EAGER_RADIUS) return
      const img = slideEl.querySelector("img[data-src]")
      if (!img) return
      img.src = img.dataset.src
      delete img.dataset.src
    })
  }

  markSlideFailed(zoom) {
    zoom.replaceChildren()
    const message = el("div", {
      class: "move-gallery__error grid h-full w-full place-items-center px-6 text-center text-muted"
    })
    message.textContent = this.labels.error
    zoom.appendChild(message)
  }

  buildChrome() {
    const chrome = el("div", {
      class: "move-gallery__chrome relative z-20 flex items-center gap-3 px-4 pt-[calc(env(safe-area-inset-top)_+_0.75rem)] pb-3"
    })

    this.caption = el("span", { class: "move-gallery__caption min-w-0 flex-1 truncate text-label-caps uppercase text-text-warm" })
    chrome.appendChild(this.caption)

    this.counter = el("span", { class: "move-gallery__counter shrink-0 text-label-caps uppercase text-muted tabular-nums" })
    chrome.appendChild(this.counter)

    this.viewBox = el("a", {
      class: "move-gallery__view-box shrink-0 rounded-full bg-card px-3 py-1.5 text-label-caps uppercase text-text-warm",
      href: "#"
    })
    this.viewBox.textContent = this.labels.viewBox
    chrome.appendChild(this.viewBox)

    this.closeButton = el("button", {
      type: "button",
      class: "move-gallery__close grid h-10 w-10 shrink-0 place-items-center rounded-full bg-card text-text-warm",
      "aria-label": this.labels.close,
      title: this.labels.close
    })
    this.closeButton.innerHTML = closeIcon
    this.closeButton.addEventListener("click", () => this.close())
    chrome.appendChild(this.closeButton)

    return chrome
  }

  buildThumbsSwiper() {
    return new Swiper(this.thumbsEl, {
      modules: [FreeMode, A11y],
      spaceBetween: 8,
      slidesPerView: "auto",
      freeMode: true,
      watchSlidesProgress: true,
      // Keep the active thumb within the strip as the main image changes.
      centeredSlides: true,
      centeredSlidesBounds: true,
      a11y: { enabled: true }
    })
  }

  buildMainSwiper(index) {
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
    return new Swiper(this.mainEl, {
      modules: [Thumbs, Zoom, Keyboard, A11y],
      initialSlide: index,
      spaceBetween: 16,
      speed: reducedMotion ? 0 : 300,
      zoom: { maxRatio: 3, toggle: true },
      keyboard: { enabled: true },
      thumbs: { swiper: this.thumbsSwiper },
      a11y: {
        enabled: true,
        prevSlideMessage: this.labels.prev,
        nextSlideMessage: this.labels.next
      },
      on: {
        slideChange: () => {
          this.syncChrome()
          this.hydrateNear()
        }
      }
    })
  }

  syncChrome() {
    const i = this.mainSwiper ? this.mainSwiper.activeIndex : this.pendingIndex
    const slide = this.slides[i]
    if (!slide) return
    this.caption.textContent = slide.caption || ""
    this.counter.textContent = format(this.labels.counter, { index: i + 1, total: this.slides.length })
    if (slide.href) this.viewBox.setAttribute("href", slide.href)
  }

  onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this.close()
      return
    }
    if (event.key !== "Tab") return
    // Focus trap — keep Tab within the dialog's controls.
    const focusable = this.focusableElements()
    if (focusable.length === 0) return
    const first = focusable[0]
    const last = focusable[focusable.length - 1]
    const active = document.activeElement
    if (event.shiftKey && active === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && active === last) {
      event.preventDefault()
      first.focus()
    } else if (!this.overlay.contains(active)) {
      event.preventDefault()
      first.focus()
    }
  }

  focusableElements() {
    if (!this.overlay) return []
    return Array.from(
      this.overlay.querySelectorAll('a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])')
    )
  }

  lockScroll() {
    this.previousBodyOverflow = document.body.style.overflow
    document.body.style.overflow = "hidden"
  }

  unlockScroll() {
    document.body.style.overflow = this.previousBodyOverflow
  }

  close() {
    this.destroy()
  }

  // Idempotent — invoked by close(), a re-entrant open(), the controller's
  // disconnect() and its turbo:before-cache teardown.
  destroy() {
    if (!this.overlay) return
    document.removeEventListener("keydown", this.onKeydown)
    this.mainSwiper?.destroy(true, true)
    this.thumbsSwiper?.destroy(true, true)
    this.mainSwiper = null
    this.thumbsSwiper = null
    this.overlay.remove()
    this.overlay = null
    this.unlockScroll()
    // Restore focus to the tile that opened the viewer (if it's still connected).
    if (this.lastFocus && document.contains(this.lastFocus)) this.lastFocus.focus()
    this.lastFocus = null
  }
}

// --- small DOM helpers -------------------------------------------------------

function el(tag, attrs = {}) {
  const node = document.createElement(tag)
  for (const [key, value] of Object.entries(attrs)) {
    if (key === "class") node.className = value
    else node.setAttribute(key, value)
  }
  return node
}

// Minimal {key} interpolation for the localized counter template. Uses {key}
// (not I18n's %{key}) so the server-side I18n.t never tries to interpolate the
// template it hands to the client.
function format(template, values) {
  return String(template).replace(/\{(\w+)\}/g, (_, key) => (key in values ? values[key] : `{${key}}`))
}

const closeIcon =
  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
  'stroke-linecap="round" stroke-linejoin="round" class="h-5 w-5" aria-hidden="true">' +
  '<path d="M18 6 6 18M6 6l12 12"/></svg>'

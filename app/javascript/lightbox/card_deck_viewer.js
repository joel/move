import Swiper from "swiper"
import { EffectCards, Zoom, Keyboard, A11y } from "swiper"

// Mobile gallery viewer (#604) — a fullscreen "effect-cards" deck
// (https://swiperjs.com/demos#effect-cards). On touch / coarse-pointer devices
// the lightbox controller lazily imports this instead of PhotoSwipe, so a phone
// never downloads the desktop viewer (and desktop never downloads Swiper).
//
// The deck reads as a stack of photos you flick through one-handed. Swiper owns
// the physics; this class owns the app shell around it: a fullscreen overlay
// appended to <body>, the caption / counter / "view box" link / close chrome
// that follows the active card, pinch/double-tap zoom (Swiper's Zoom module —
// parity with PhotoSwipe), keyboard + a11y, a focus trap, ESC / backdrop close,
// body-scroll lock and reduced-motion fallback. Like PhotoSwipe it lives outside
// the Turbo-cached DOM, so the controller tears it down on turbo:before-cache.
//
// slides: [{ src, thumb, caption, href, tile }] built by the controller from the
// grid tiles — src is the :detail image, thumb the already-loaded grid thumb.

// How near the active card an image is eagerly loaded; the rest stay lazy.
const EAGER_RADIUS = 1

export class CardDeckViewer {
  constructor(labels) {
    this.labels = labels
    this.overlay = null
    this.swiper = null
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
    // Stashed before buildOverlay so buildSlide (which runs before buildSwiper)
    // can decide eager/lazy loading against the opened index.
    this.pendingIndex = index
    this.lastFocus = document.activeElement
    this.overlay = this.buildOverlay(slides)
    document.body.appendChild(this.overlay)
    this.lockScroll()
    this.swiper = this.buildSwiper(index)
    this.syncChrome()
    document.addEventListener("keydown", this.onKeydown)
    // Focus the close control so ESC/keyboard and the focus trap have an anchor
    // inside the dialog; guard for the rare null (element not yet laid out).
    this.closeButton?.focus()
  }

  buildOverlay(slides) {
    const overlay = el("div", {
      class: "move-deck fixed inset-0 z-[1000] flex flex-col bg-page/95 backdrop-blur-sm",
      role: "dialog",
      "aria-modal": "true",
      "aria-label": this.labels.dialog
    })

    // Backdrop — a tap outside the card dismisses. It sits behind the deck and
    // chrome (which stopPropagation is unnecessary for: they're siblings above).
    const backdrop = el("div", { class: "move-deck__backdrop absolute inset-0", "aria-hidden": "true" })
    backdrop.addEventListener("click", () => this.close())
    overlay.appendChild(backdrop)

    overlay.appendChild(this.buildChrome())

    // EffectCards sizes each card to the container, so it needs an explicit
    // height as well as width — without one the deck collapses to zero height.
    const swiperEl = el("div", {
      class: "move-deck__swiper swiper relative z-10 mx-auto my-auto w-[86vw] max-w-[480px] h-[68vh] max-h-[560px]"
    })
    const wrapper = el("div", { class: "swiper-wrapper" })
    slides.forEach((slide, i) => wrapper.appendChild(this.buildSlide(slide, i)))
    swiperEl.appendChild(wrapper)
    overlay.appendChild(swiperEl)
    this.swiperEl = swiperEl

    return overlay
  }

  buildSlide(slide, i) {
    const slideEl = el("div", {
      class: "move-deck__slide swiper-slide flex items-center justify-center overflow-hidden " +
             "rounded-[18px] bg-surface-container-high"
    })
    const zoom = el("div", { class: "swiper-zoom-container h-full w-full" })
    // Thumb as an instant backdrop so the card is never blank while :detail
    // loads (the deck's thumb-first equivalent of PhotoSwipe's msrc placeholder).
    if (slide.thumb) {
      zoom.style.backgroundImage = `url("${cssUrl(slide.thumb)}")`
      zoom.style.backgroundSize = "contain"
      zoom.style.backgroundRepeat = "no-repeat"
      zoom.style.backgroundPosition = "center"
    }
    const img = el("img", {
      class: "h-full w-full object-contain",
      src: slide.src,
      alt: slide.caption || "",
      // Eager for the opened card and its neighbours; lazy for the rest of the
      // deck so a large gallery doesn't fetch every :detail up front.
      loading: Math.abs(i - this.pendingIndex) <= EAGER_RADIUS ? "eager" : "lazy",
      draggable: "false"
    })
    // Parity with the desktop lightbox's errorMsg: if the :detail image fails
    // (e.g. an expired signed URL), show the localized error instead of a broken
    // image. The thumb backdrop is cleared too — it's a same-expiry signed URL,
    // so it has almost certainly failed as well.
    img.addEventListener("error", () => this.markSlideFailed(zoom), { once: true })
    zoom.appendChild(img)
    slideEl.appendChild(zoom)
    return slideEl
  }

  markSlideFailed(zoom) {
    zoom.replaceChildren()
    zoom.style.backgroundImage = "none"
    const message = el("div", {
      class: "move-deck__error grid h-full w-full place-items-center px-6 text-center text-muted"
    })
    message.textContent = this.labels.error
    zoom.appendChild(message)
  }

  buildChrome() {
    const chrome = el("div", {
      class: "move-deck__chrome relative z-20 flex items-center gap-3 px-4 pt-[calc(env(safe-area-inset-top)_+_0.75rem)] pb-3"
    })

    this.caption = el("span", { class: "move-deck__caption min-w-0 flex-1 truncate text-label-caps uppercase text-text-warm" })
    chrome.appendChild(this.caption)

    this.counter = el("span", { class: "move-deck__counter shrink-0 text-label-caps uppercase text-muted tabular-nums" })
    chrome.appendChild(this.counter)

    this.viewBox = el("a", {
      class: "move-deck__view-box shrink-0 rounded-full bg-card px-3 py-1.5 text-label-caps uppercase text-text-warm",
      href: "#"
    })
    this.viewBox.textContent = this.labels.viewBox
    chrome.appendChild(this.viewBox)

    this.closeButton = el("button", {
      type: "button",
      class: "move-deck__close grid h-10 w-10 shrink-0 place-items-center rounded-full bg-card text-text-warm",
      "aria-label": this.labels.close,
      title: this.labels.close
    })
    this.closeButton.innerHTML = closeIcon
    this.closeButton.addEventListener("click", () => this.close())
    chrome.appendChild(this.closeButton)

    return chrome
  }

  buildSwiper(index) {
    const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)").matches
    return new Swiper(this.swiperEl, {
      modules: [EffectCards, Zoom, Keyboard, A11y],
      // Reduced motion: drop the rotating-stack animation for a plain, instant
      // slide so the interaction still works without the flourish.
      effect: reducedMotion ? "slide" : "cards",
      cardsEffect: { perSlideOffset: 8, perSlideRotate: 2, slideShadows: true },
      speed: reducedMotion ? 0 : 300,
      initialSlide: index,
      grabCursor: true,
      // Loop is unnecessary for a deck and interacts badly with effect-cards'
      // finite stack; the ends simply stop.
      zoom: { maxRatio: 3, toggle: true },
      keyboard: { enabled: true },
      a11y: {
        enabled: true,
        prevSlideMessage: this.labels.prev,
        nextSlideMessage: this.labels.next
      },
      on: { slideChange: () => this.syncChrome() }
    })
  }

  syncChrome() {
    const i = this.swiper ? this.swiper.activeIndex : (this.pendingIndex || 0)
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
    // Focus trap — keep Tab within the dialog's controls (view-box link, close).
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
    this.swiper?.destroy(true, true)
    this.swiper = null
    this.overlay.remove()
    this.overlay = null
    this.unlockScroll()
    // Restore focus to the tile that opened the deck (if it's still connected).
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

// Guard a URL for use inside a CSS url("…") — thumb URLs are app-signed R2 URLs
// (no quotes/parens/newlines), but escape defensively so a stray character can't
// break out of the declaration.
function cssUrl(url) {
  return String(url).replace(/["\\\n\r]/g, "\\$&")
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

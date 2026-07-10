import { Controller } from "@hotwired/stimulus"

// Gallery lightbox. A single native <dialog> viewer shared by every grid tile.
// Each tile is a target carrying the photo's :thumb/:detail srcs, caption and box
// href as data-*; opening reads the clicked tile. showModal() gives focus-trap,
// Escape and the ::backdrop for free.
//
// Navigation is a 3-slide draggable track (prev / current / next, wrapping):
// neighbours are real <img>s so they preload once shown, and a finger drag
// follows the touch, committing past a distance or flick threshold. Every slide
// renders thumb-first — the grid's :thumb is usually already in the browser
// cache, so the photo changes instantly and sharpens when :detail lands (LQIP).
// Arrow buttons (fine pointers only) and ArrowLeft/Right reuse the same slide
// animation.
//
//   div(data: { controller: "lightbox", action: "turbo:before-cache@document->lightbox#close" })
//     button(data: { lightbox_target: "tile", action: "click->lightbox#open", src/thumb/caption/href })
//     dialog(data: { lightbox_target: "dialog", action: "keydown->lightbox#key close->lightbox#closed touch...:passive" })
//       div(track target) > 3 × img(data-lightbox-target="slide"), span(caption), a(link)

// Commit a drag past this fraction of the track width…
const COMMIT_RATIO = 0.2
// …or past this velocity (px/ms) — a short, fast flick.
const FLICK_VELOCITY = 0.5
// Movement below this (px) hasn't chosen an axis yet — taps stay taps.
const AXIS_SLOP = 8
// Detail upgrades start this long after a render settles, so flying past photos
// (each turn bumps seq before the timer fires) never fetches their full images.
const DETAIL_DELAY = 100

export default class extends Controller {
  static targets = ["tile", "dialog", "track", "slide", "caption", "link"]

  connect() {
    // Detail loads are guarded by a token: any render or close bumps it, so a
    // stale in-flight load can never overwrite a newer slide (or a closed viewer).
    this.seq = 0
    // Detail URLs that finished loading — skip the thumb-first step for them so
    // re-rendering a slide (after a turn) doesn't flash back to the blurry thumb.
    this.loaded = new Set()
    this.animationId = 0
    this.animating = false
    this.pendingFinish = null
    this.gesture = null
    this.detailTimer = null
  }

  open(event) {
    this.index = this.tileTargets.indexOf(event.currentTarget)
    if (this.index < 0) this.index = 0
    this.resetTrack()
    this.render()
    this.dialogTarget.showModal()
  }

  close() {
    this.teardown()
    this.dialogTarget.close()
  }

  // The dialog's native close event — fires on Escape too, which never goes
  // through close(); teardown is idempotent so both paths can run.
  closed() {
    this.teardown()
  }

  teardown() {
    this.seq += 1
    this.animationId += 1
    this.animating = false
    this.pendingFinish = null
    this.gesture = null
    clearTimeout(this.detailTimer)
    // Drop the heavy images so they aren't held in memory between views.
    this.slideTargets.forEach((img) => img.removeAttribute("src"))
  }

  next() {
    this.slideTo(1)
  }

  prev() {
    this.slideTo(-1)
  }

  // Fill the 3 slides from the tiles around the current index and point the
  // caption/link at the current photo. Detail upgrades are deferred behind one
  // seq-guarded timer (see DETAIL_DELAY).
  render() {
    this.seq += 1
    const seq = this.seq
    clearTimeout(this.detailTimer)

    const upgrades = []
    this.slideTargets.forEach((img, position) => {
      const upgrade = this.renderSlide(img, this.tileAt(this.index + position - 1), position === 1)
      if (upgrade) upgrades.push(upgrade)
    })
    this.updateMeta(this.tileAt(this.index))

    if (upgrades.length === 0) return
    this.detailTimer = setTimeout(() => {
      if (seq !== this.seq) return
      upgrades.forEach(({ img, src }) => this.loadDetail(img, src, seq))
    }, DETAIL_DELAY)
  }

  // Thumb-first: show the (grid-cached) thumb immediately; return the pending
  // :detail upgrade for render() to schedule. Only the centre slide is exposed
  // to assistive tech — the offscreen neighbours are visual preloads, and
  // announcing all three would read three photos for the one on screen.
  renderSlide(img, tile, current) {
    const { src, thumb, caption } = tile?.dataset || {}
    const initial = this.loaded.has(src) ? src : thumb || src
    // Clear rather than retain the previous photo when a tile has no image, so
    // the viewer never shows the wrong photo under the new caption.
    if (initial) img.src = initial
    else img.removeAttribute("src")
    img.alt = current ? caption || "" : ""
    img.setAttribute("aria-hidden", current ? "false" : "true")

    if (!src || src === initial) return null
    return { img, src }
  }

  // No onerror handling — deliberate: an expired detail URL (the signed URL's
  // TTL) simply leaves the thumb showing.
  loadDetail(img, src, seq) {
    const loader = new Image()
    loader.onload = () => {
      this.loaded.add(src)
      if (seq === this.seq) img.src = src
    }
    loader.src = src
  }

  // The caption and "view box" link describe the photo the user is looking at —
  // updated the moment a turn commits (not when its animation ends), so a tap on
  // "view box" mid-animation can never open the previous photo's box.
  updateMeta(tile) {
    const { caption, href } = tile?.dataset || {}
    if (this.hasCaptionTarget) this.captionTarget.textContent = caption || ""
    if (this.hasLinkTarget && href) this.linkTarget.href = href
  }

  tileAt(index) {
    const count = this.tileTargets.length
    if (count === 0) return null
    return this.tileTargets[((index % count) + count) % count]
  }

  // Animate the track one slide left/right, then recentre it around the new
  // index. A request landing mid-animation fast-forwards the pending turn
  // instead of being dropped, so key-repeat zips through the set.
  slideTo(step) {
    // A live drag must not fight the animation over the transform (hybrid
    // devices: finger down + arrow key/button).
    this.gesture = null
    if (this.tileTargets.length === 0) return
    if (this.animating) this.pendingFinish?.()
    if (this.animating) return
    this.animating = true
    const id = (this.animationId += 1)
    let timer = null
    let onTransitionEnd = null

    const finish = () => {
      clearTimeout(timer)
      if (onTransitionEnd) this.trackTarget.removeEventListener("transitionend", onTransitionEnd)
      // The id makes finish one-shot per animation: a stale transitionend or
      // safety timer from an earlier turn can never cut a newer one short.
      if (id !== this.animationId || !this.animating) return
      this.animating = false
      this.pendingFinish = null
      this.index += step // tileAt() wraps every read, so the raw sum is fine
      this.resetTrack()
      this.render()
    }
    this.pendingFinish = finish
    // Filtered so a transitionend bubbling from a future slide/img transition
    // can never cut the turn short — only the track's own transform counts.
    onTransitionEnd = (event) => {
      if (event.target !== this.trackTarget || event.propertyName !== "transform") return
      finish()
    }

    this.updateMeta(this.tileAt(this.index + step))
    this.trackTarget.style.transition = ""
    // This read doubles as the style flush that re-arms the CSS transition
    // after a drag set transition:none — do not remove it as "just a lookup".
    const duration = parseFloat(getComputedStyle(this.trackTarget).transitionDuration) || 0
    this.trackTarget.style.transform = `translateX(${step === 1 ? "-200%" : "0%"})`
    if (duration === 0) {
      // prefers-reduced-motion (or a hidden dialog): no transition will run, so
      // no transitionend — recentre synchronously.
      finish()
    } else {
      this.trackTarget.addEventListener("transitionend", onTransitionEnd)
      // Safety net: transitionend can be swallowed (tab hidden, dialog closed,
      // or a drag released exactly one track-width out so the transform doesn't
      // change).
      timer = setTimeout(finish, duration * 1000 + 100)
    }
  }

  // Snap the track back to the centre slide without animating. Synchronous —
  // the forced reflow between the transition:none write and its restore keeps
  // the jump invisible without leaving an async window that could clobber a
  // following touchstart's transition:none (rapid consecutive swipes).
  resetTrack() {
    this.trackTarget.style.transition = "none"
    this.trackTarget.style.transform = "translateX(-100%)"
    void this.trackTarget.offsetWidth
    this.trackTarget.style.transition = ""
  }

  // ── Follow-finger drag ──────────────────────────────────────────────
  // Single-touch only: a second finger landing mid-drag abandons the gesture
  // and recentres (pinch-zoom must not end in a page turn). The first
  // significant movement locks the axis; vertical intent abandons the drag.
  // All handlers are passive — we never preventDefault.

  touchStart(event) {
    if (event.touches.length > 1) {
      // Only settle when a drag was actually in progress: gesture implies not
      // animating, so the recentre can't fight a running turn.
      if (this.gesture) this.abandonDrag()
      return
    }
    // Grabbing the track mid-turn completes the turn instantly and starts the
    // drag from the settled position.
    if (this.animating) this.pendingFinish?.()
    if (this.animating) return
    const touch = event.touches[0]
    this.gesture = { x: touch.clientX, y: touch.clientY, time: event.timeStamp, axis: null, dx: 0 }
    this.trackTarget.style.transition = "none"
  }

  touchMove(event) {
    const gesture = this.gesture
    if (!gesture) return
    if (event.touches.length > 1) {
      this.abandonDrag()
      return
    }

    const touch = event.touches[0]
    const dx = touch.clientX - gesture.x
    const dy = touch.clientY - gesture.y
    if (!gesture.axis) {
      if (Math.abs(dx) < AXIS_SLOP && Math.abs(dy) < AXIS_SLOP) return
      gesture.axis = Math.abs(dx) > Math.abs(dy) ? "x" : "y"
      if (gesture.axis === "y") {
        this.abandonDrag()
        return
      }
    }

    gesture.dx = dx
    this.trackTarget.style.transform = `translateX(calc(-100% + ${dx}px))`
  }

  touchEnd(event) {
    const gesture = this.gesture
    this.gesture = null
    if (!gesture) return
    if (gesture.axis !== "x") {
      // A tap (no axis chosen): just restore the transition killed on touchstart.
      this.trackTarget.style.transition = ""
      return
    }

    const width = this.trackTarget.clientWidth || 1
    const elapsed = Math.max(event.timeStamp - gesture.time, 1)
    const commits = Math.abs(gesture.dx) > width * COMMIT_RATIO ||
      Math.abs(gesture.dx) / elapsed > FLICK_VELOCITY
    if (commits) this.slideTo(gesture.dx < 0 ? 1 : -1)
    else this.settle()
  }

  touchCancel() {
    this.abandonDrag()
  }

  abandonDrag() {
    this.gesture = null
    this.settle()
  }

  // Animate the track back to the centre slide (an uncommitted drag).
  settle() {
    this.trackTarget.style.transition = ""
    this.trackTarget.style.transform = "translateX(-100%)"
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
  // control) closes the viewer. The track is pointer-events-none (images opt
  // back in), so clicks on empty slide area reach the wrapper.
  backdropClose(event) {
    if (event.target === event.currentTarget) this.close()
  }
}

import { Controller } from "@hotwired/stimulus"

// Per-photo review (C2): auto-saves an item's name as it's edited inline.
//   div(data: { controller: "inline-rename", inline_rename_url_value: rename_path,
//               inline_rename_version_value: <item version> })
//     input(data: { inline_rename_target: "input",
//                   action: "blur->inline-rename#save keydown.enter->inline-rename#blur" })
//     button(data: { action: "inline-rename#focus" })   // pencil: focus + select all
//
// Edits set a wanted name and the server is converged to it: at most one PATCH
// per item is in flight, and when it resolves the next wanted name (if it moved
// meanwhile) is sent. This handles every interleaving consistently — rapid edits,
// a revert to an earlier value while a newer save is still in flight, and
// navigating away mid-save — without the field and the database diverging
// (#149/#151/#152). Each PATCH uses keepalive so a save triggered by clicking
// "Next Photo" still completes after Turbo navigates. A blank value is invalid
// (name required): the field snaps back to the value being saved.
//
// Blur alone is not a reliable commit trigger: iOS Safari doesn't blur a focused
// input when a button is tapped, so a dirty edit could ride into "Mark as
// Reviewed"'s redirect unsent (#690). The controller therefore also flushes on
// every Turbo exit — submit-start (any form on the page, including the mark
// button_to), before-visit (Ignore/Next/back links), and before-cache (history
// restores, which before-visit skips) — and on disconnect. save() is idempotent.
//
// Server echo (#692): a Turbo Stream replacing the item list (an add landing)
// renders rows from a DB snapshot that may predate a rename's commit, and the
// rename may settle before OR after that list arrives. So the convergence state
// lives here at module level, not in the (replaceable) controller:
//   - `confirmed`: the newest server state seen per item — the rename response
//     echoes the canonical { name, version }, and every rendered row carries its
//     own version. A row connecting with an OLDER version than the echo shows the
//     echoed name; a newer one (a fresh visit, an edit elsewhere) wins.
//   - `sessions`: the PATCH in flight + the next wanted name per item, so a
//     second edit typed inside the window, or flushed by a torn-down row, is
//     still sent — serialized behind the first, never racing it.
// Every settlement is announced on `document`; whichever controller currently
// shows the item re-syncs from it (and reverts + flags on failure, #147).
const SETTLED = "inline-rename:settled"
const confirmed = new Map() // url -> { name, version }
const sessions = new Map() // url -> { sending: name | null, wanted: name }
// Items whose last rename failed, until a new edit or a later success supersedes
// it — or the reviewer returns to the field: a row connecting in a list
// replacement re-applies the error flag (#147) rather than looking saved.
const failedRenames = new Set()

// Record a server-confirmed state, keeping only the newest per item.
function confirm(url, state) {
  const known = confirmed.get(url)
  if (!known || state.version >= known.version) confirmed.set(url, state)
}

// The name the item is converging to: the queued edit, else the confirmed one.
function intentFor(url) {
  return sessions.get(url)?.wanted ?? confirmed.get(url)?.name
}

function want(url, name) {
  const session = sessions.get(url) ?? { sending: null, wanted: name }
  session.wanted = name
  sessions.set(url, session)
  failedRenames.delete(url) // a fresh edit supersedes the failure
  pump(url)
}

// Send the wanted name unless a request is already in flight (its settlement
// pumps again) or the server already holds it.
function pump(url) {
  const session = sessions.get(url)
  if (!session || session.sending !== null) return
  if (session.wanted === confirmed.get(url)?.name) {
    sessions.delete(url)
    return
  }
  const name = session.wanted
  session.sending = name
  patch(url, name)
    .then((state) => {
      confirm(url, state)
      // The server may canonicalize: follow its echo unless the user moved on.
      if (session.wanted === name) session.wanted = state.name
      session.sending = null
      failedRenames.delete(url)
      announce(url, true)
      pump(url)
    })
    .catch(() => {
      sessions.delete(url) // a refused save drops the pending change (#147)
      failedRenames.add(url) // kept even if no row is on the page to see it now
      announce(url, false)
    })
}

function patch(url, name) {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  return fetch(url, {
    method: "PATCH",
    keepalive: true,
    headers: { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token },
    body: JSON.stringify({ name }),
  }).then((response) => {
    if (!response.ok) throw new Error(`rename failed: ${response.status}`)
    return response.json()
  })
}

function announce(url, ok) {
  document.dispatchEvent(new CustomEvent(SETTLED, { detail: { url, ok } }))
}

export default class extends Controller {
  static values = { url: String, version: Number }
  static targets = ["input"]

  connect() {
    this.url = this.urlValue // captured so a flush can still fire after teardown
    confirm(this.url, { name: this.inputTarget.value, version: this.versionValue })
    if (failedRenames.has(this.url)) this.#settled(false)
    else this.#show(intentFor(this.url))

    this.flush = () => {
      if (this.hasInputTarget) this.save()
    }
    this.settled = (event) => {
      if (event.detail.url === this.url) this.#settled(event.detail.ok)
    }
    document.addEventListener("turbo:submit-start", this.flush)
    document.addEventListener("turbo:before-visit", this.flush)
    document.addEventListener("turbo:before-cache", this.flush)
    document.addEventListener(SETTLED, this.settled)
  }

  // Teardown is the last chance to flush: a Turbo Stream replacing the item
  // list (e.g. an add landing) fires none of the document events above, yet
  // destroys a dirty field with it. The input's typed value is still readable
  // on the detached subtree, and the module-level session outlives the row.
  disconnect() {
    this.flush()
    document.removeEventListener("turbo:submit-start", this.flush)
    document.removeEventListener("turbo:before-visit", this.flush)
    document.removeEventListener("turbo:before-cache", this.flush)
    document.removeEventListener(SETTLED, this.settled)
  }

  // Pencil icon: focus the field and select all so typing replaces the label.
  focus() {
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  // Enter commits by blurring, which triggers #save.
  blur() {
    this.inputTarget.blur()
  }

  // Clear a prior error state when the reviewer returns to edit the field.
  clearError() {
    failedRenames.delete(this.url)
    this.inputTarget.classList.remove("ring-2", "ring-error")
    this.inputTarget.removeAttribute("aria-invalid")
  }

  save() {
    const name = this.inputTarget.value.trim()
    const intent = intentFor(this.url)
    // Blank is invalid (name required) and an unchanged intent needs no request:
    // either way normalize the field (e.g. drop trailing whitespace) to it.
    if (name === "" || name === intent) {
      this.#show(intent)
      return
    }
    this.shown = name
    want(this.url, name)
  }

  #settled(ok) {
    if (!this.hasInputTarget) return
    if (!ok) {
      // Server refused (or network error): back to the last confirmed value,
      // flagged so a failed save isn't silently lost (#147) — even when the
      // request was sent by a row a list replacement has since torn down.
      this.#show(confirmed.get(this.url).name)
      this.inputTarget.classList.add("ring-2", "ring-error")
      this.inputTarget.setAttribute("aria-invalid", "true")
      return
    }
    // Re-sync to the echo — unless the reviewer is mid-edit (typed since the
    // last value we showed), whose own save will converge it.
    if (this.inputTarget.value.trim() === this.shown) this.#show(intentFor(this.url))
  }

  #show(name) {
    this.shown = name
    if (this.inputTarget.value !== name) this.inputTarget.value = name
  }
}

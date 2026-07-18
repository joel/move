import { Controller } from "@hotwired/stimulus"

// Per-photo review (C2): auto-saves an item's name as it's edited inline.
//   div(data: { controller: "inline-rename", inline_rename_url_value: rename_path })
//     input(data: { inline_rename_target: "input",
//                   action: "blur->inline-rename#save keydown.enter->inline-rename#blur" })
//     button(data: { action: "inline-rename#focus" })   // pencil: focus + select all
//
// Edits set `target` and the controller converges the server to it: at most one
// PATCH is in flight, and when it resolves the controller re-syncs if `target`
// moved meanwhile. This handles every interleaving consistently — rapid edits, a
// revert to an earlier value while a newer save is still in flight, and navigating
// away mid-save — without the field and the database diverging (#149/#151/#152).
// Each PATCH uses keepalive so a save triggered by clicking "Next Photo" still
// completes after Turbo navigates. A blank value is invalid (name required): the
// field snaps back to the value being saved.
//
// Blur alone is not a reliable commit trigger: iOS Safari doesn't blur a focused
// input when a button is tapped, so a dirty edit could ride into "Mark as
// Reviewed"'s redirect unsent (#690). The controller therefore also flushes on
// every Turbo exit — submit-start (any form on the page, including the mark
// button_to), before-visit (Ignore/Next/back links), and before-cache (history
// restores, which before-visit skips). save() is idempotent, so the eventual
// real blur or overlapping events cost nothing.
// Renames whose PATCH is still in flight, keyed by endpoint. A Turbo Stream
// replacing the item list (an add landing) renders rows from a DB snapshot
// that may predate the PATCH commit; the replacement controller adopts the
// pending value from here on connect so the visible field never regresses to
// the stale snapshot. A failed PATCH after such a replacement stays invisible
// (#692) — the map only bridges the success path across teardown.
const inFlightRenames = new Map()

export default class extends Controller {
  static values = { url: String }
  static targets = ["input"]

  connect() {
    this.committed = this.inputTarget.value // last value the server confirmed
    this.target = this.committed // value the field + server should converge to
    this.url = this.urlValue // captured so a flush can still fire after teardown
    this.saving = false
    const pending = inFlightRenames.get(this.url)
    if (pending !== undefined && pending !== this.committed) {
      // A save for this item is mid-flight across a list replacement: show
      // the value being saved, not the snapshot the server rendered.
      this.inputTarget.value = pending
      this.target = pending
      this.committed = pending
    }
    this.flush = () => {
      if (this.hasInputTarget) this.save()
    }
    document.addEventListener("turbo:submit-start", this.flush)
    document.addEventListener("turbo:before-visit", this.flush)
    document.addEventListener("turbo:before-cache", this.flush)
  }

  // Teardown is the last chance to flush: a Turbo Stream replacing the item
  // list (e.g. an add landing) fires none of the document events above, yet
  // destroys a dirty field with it. The input's typed value is still readable
  // on the detached subtree, and the keepalive PATCH outlives the controller.
  disconnect() {
    this.flush()
    document.removeEventListener("turbo:submit-start", this.flush)
    document.removeEventListener("turbo:before-visit", this.flush)
    document.removeEventListener("turbo:before-cache", this.flush)
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
    this.inputTarget.classList.remove("ring-2", "ring-error")
    this.inputTarget.removeAttribute("aria-invalid")
  }

  save() {
    const name = this.inputTarget.value.trim()
    if (name === "") {
      // Name is required — snap back to the value we're converging to rather than
      // sending an empty name.
      this.inputTarget.value = this.target
      return
    }
    if (name === this.target) {
      // No change in intent — normalize the field (e.g. drop trailing whitespace)
      // so what's shown matches the saved value.
      this.inputTarget.value = this.target
      return
    }
    this.target = name
    this.#sync()
  }

  // Drive the server toward `target`, one request at a time.
  #sync() {
    if (this.saving || this.target === this.committed) return
    this.saving = true
    const name = this.target
    inFlightRenames.set(this.url, name)

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.url, {
      method: "PATCH",
      keepalive: true,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({ name }),
    })
      .then((response) => {
        this.saving = false
        if (inFlightRenames.get(this.url) === name) inFlightRenames.delete(this.url)
        if (response.ok) {
          this.committed = name
          this.#sync() // target moved while saving? converge again
        } else {
          this.#revert()
        }
      })
      .catch(() => {
        this.saving = false
        if (inFlightRenames.get(this.url) === name) inFlightRenames.delete(this.url)
        this.#revert()
      })
  }

  // Server refused (or network error): drop the desired change back to the last
  // confirmed value and flag the field so a failed save isn't silently lost (#147).
  #revert() {
    this.target = this.committed
    // The controller may have been torn down by navigation before the response.
    if (!this.hasInputTarget) return

    this.inputTarget.value = this.committed
    this.inputTarget.classList.add("ring-2", "ring-error")
    this.inputTarget.setAttribute("aria-invalid", "true")
  }
}

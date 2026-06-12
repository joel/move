import { Controller } from "@hotwired/stimulus"

// Per-photo review (C2): auto-saves an item's name as it's edited inline.
//   div(data: { controller: "inline-rename", inline_rename_url_value: rename_path })
//     input(data: { inline_rename_target: "input",
//                   action: "blur->inline-rename#save keydown.enter->inline-rename#blur" })
//     button(data: { action: "inline-rename#focus" })   // pencil: focus + select all
//
// Writes are SERIALIZED per field: only one rename PATCH is in flight at a time,
// and a rapid second edit is queued as the latest pending value (#149). This
// guarantees the server applies edits in order (no concurrent requests to
// reorder) and the newest edit wins — without relying on client-side aborts,
// which can't stop a request the server already received. Each request uses
// `keepalive: true` so a save triggered by clicking "Next Photo" still completes
// after Turbo navigates away. A blank value is never saved (name is required) —
// the field reverts.
export default class extends Controller {
  static values = { url: String }
  static targets = ["input"]

  connect() {
    this.last = this.inputTarget.value
    // Capture the endpoint so a queued flush can still fire after Turbo tears the
    // controller down mid-navigation.
    this.url = this.urlValue
    this.pending = null
    this.inFlight = false
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
    if (name === "" || name === this.last) {
      this.inputTarget.value = this.last
      return
    }
    // Queue the latest value; #flush sends it once no request is in flight.
    this.pending = name
    if (!this.inFlight) this.#flush()
  }

  #flush() {
    const name = this.pending
    this.pending = null
    if (name == null || name === this.last) {
      this.inFlight = false
      return
    }
    this.inFlight = true
    const previous = this.last

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
        this.inFlight = false
        if (response.ok) {
          // Commit only once the server confirms it, then send the next queued
          // edit (if any) — keeping writes ordered and the field in sync (#149).
          this.last = name
          if (this.pending != null) this.#flush()
        } else {
          // A rejected name reverts the field and flags it; stop the chain so a
          // failure isn't silently overwritten (#147).
          this.pending = null
          this.#reject(previous)
        }
      })
      .catch(() => {
        this.inFlight = false
        this.pending = null
        this.#reject(previous)
      })
  }

  #reject(previous) {
    // The controller may have been torn down by navigation before a response
    // arrived; nothing to revert if the field is gone.
    if (!this.hasInputTarget) return

    this.inputTarget.value = previous
    this.inputTarget.classList.add("ring-2", "ring-error")
    this.inputTarget.setAttribute("aria-invalid", "true")
  }
}

import { Controller } from "@hotwired/stimulus"

// Per-photo review (C2): auto-saves an item's name as it's edited inline.
//   div(data: { controller: "inline-rename", inline_rename_url_value: rename_path })
//     input(data: { inline_rename_target: "input",
//                   action: "blur->inline-rename#save keydown.enter->inline-rename#blur" })
//     button(data: { action: "inline-rename#focus" })   // pencil: focus + select all
//
// Save fires on blur with `keepalive: true` so it still reaches the server when
// the blur was caused by clicking "Next Photo" (the navigation won't drop it).
// A blank value is never saved (name is required) — the field reverts.
export default class extends Controller {
  static values = { url: String }
  static targets = ["input"]

  connect() {
    this.last = this.inputTarget.value
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

  disconnect() {
    this.controller?.abort()
  }

  save() {
    const name = this.inputTarget.value.trim()
    if (name === "" || name === this.last) {
      this.inputTarget.value = this.last
      return
    }
    const previous = this.last

    // Supersede any in-flight save for this field: a rapid second edit aborts the
    // first, so a slower/older response can't run #reject and revert a newer
    // accepted value (#149). The latest request still uses keepalive so it
    // survives navigating to the next photo.
    this.controller?.abort()
    this.controller = new AbortController()

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "PATCH",
      keepalive: true,
      signal: this.controller.signal,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({ name }),
    })
      // Commit the new value only once the server confirms it; on a rejected
      // name revert to the last saved value and flag the field so the save isn't
      // silently lost (#147). A superseded request rejects with AbortError and is
      // ignored so it can't clobber the newer edit (#149).
      .then((response) => {
        if (response.ok) {
          this.last = name
        } else {
          this.#reject(previous)
        }
      })
      .catch((error) => {
        if (error.name !== "AbortError") this.#reject(previous)
      })
  }

  #reject(previous) {
    this.inputTarget.value = previous
    this.inputTarget.classList.add("ring-2", "ring-error")
    this.inputTarget.setAttribute("aria-invalid", "true")
  }
}

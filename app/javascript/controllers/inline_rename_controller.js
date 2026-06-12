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

  save() {
    const name = this.inputTarget.value.trim()
    if (name === "" || name === this.last) {
      this.inputTarget.value = this.last
      return
    }
    this.last = name

    const token = document.querySelector('meta[name="csrf-token"]')?.content
    fetch(this.urlValue, {
      method: "PATCH",
      keepalive: true,
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": token,
      },
      body: JSON.stringify({ name }),
    })
  }
}

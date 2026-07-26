// Minimal {key} interpolation for localized templates filled in on the client
// (per-slide values the server can't know). Uses {key} — NOT I18n's %{key} —
// so the server-side I18n.t never tries to interpolate the template it hands
// to the client. Shared by both lightbox viewers.
export function format(template, values) {
  return String(template).replace(/\{(\w+)\}/g, (_, key) => (key in values ? values[key] : `{${key}}`))
}

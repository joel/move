// Move — Design Foundation tokens (Phase D0).
//
// NOTE: This project runs Tailwind CSS v4, which is CSS-first. The authoritative
// token definitions live in `app/assets/tailwind/application.css` (`@theme` +
// runtime `--c-*` variables). This file mirrors those tokens by canonical name
// for documentation and tooling that still reads a JS config. Keep the two in
// sync; the CSS file wins at build time. Source: Stitch "Move Design"
// designTheme.designMd (see `doc/phases/Phase D0 - Design Foundation.md` §4).
module.exports = {
  content: [
    "./app/views/**/*.{erb,html,rb}",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/components/**/*.{erb,rb}"
  ],
  darkMode: "class",
  theme: {
    extend: {
      // §4.1/§4.2 — surfaces/accent (Refined Palette) + Material-3 state ramp.
      // Values reference the theme-swapped CSS variables defined in the CSS file.
      colors: {
        page: "var(--c-page)",
        card: "var(--c-card)",
        "card-border": "var(--c-card-border)",
        "accent-sage": "var(--c-accent-sage)",
        "text-warm": "var(--c-text-warm)",
        muted: "var(--c-muted)",
        primary: "var(--c-primary)",
        "on-primary": "var(--c-on-primary)",
        "primary-container": "var(--c-primary-container)",
        "on-primary-container": "var(--c-on-primary-container)",
        secondary: "var(--c-secondary)",
        "on-secondary": "var(--c-on-secondary)",
        "secondary-container": "var(--c-secondary-container)",
        "on-secondary-container": "var(--c-on-secondary-container)",
        tertiary: "var(--c-tertiary)",
        "on-tertiary": "var(--c-on-tertiary)",
        "tertiary-container": "var(--c-tertiary-container)",
        error: "var(--c-error)",
        "on-error": "var(--c-on-error)",
        "error-container": "var(--c-error-container)",
        "on-error-container": "var(--c-on-error-container)",
        surface: "var(--c-surface)",
        "surface-container": "var(--c-surface-container)",
        "surface-container-high": "var(--c-surface-container-high)",
        "surface-container-highest": "var(--c-surface-container-highest)",
        "on-surface": "var(--c-on-surface)",
        "on-surface-variant": "var(--c-on-surface-variant)",
        outline: "var(--c-outline)",
        "outline-variant": "var(--c-outline-variant)"
      },
      // §4.4 — cards/inputs use `card` (20px); buttons/chips/progress = full.
      borderRadius: {
        sm: "0.25rem",
        DEFAULT: "0.5rem",
        md: "0.75rem",
        lg: "1rem",
        xl: "1.5rem",
        card: "1.25rem",
        full: "9999px"
      },
      // §4.5 — 4px baseline + named rhythm.
      spacing: {
        "margin-mobile": "20px",
        "margin-desktop": "48px",
        gutter: "16px",
        "stack-gap": "12px",
        "section-gap": "32px"
      },
      // §4.3 — Plus Jakarta Sans typographic scale.
      fontFamily: {
        sans: ["Plus Jakarta Sans", "Segoe UI", "ui-sans-serif", "system-ui", "sans-serif"]
      },
      fontSize: {
        "headline-xl": ["40px", { lineHeight: "48px", letterSpacing: "-0.02em", fontWeight: "700" }],
        "headline-lg": ["32px", { lineHeight: "40px", letterSpacing: "-0.01em", fontWeight: "700" }],
        "headline-lg-mobile": ["28px", { lineHeight: "36px", fontWeight: "700" }],
        "headline-md": ["24px", { lineHeight: "32px", fontWeight: "600" }],
        "body-lg": ["18px", { lineHeight: "28px", fontWeight: "400" }],
        "body-md": ["16px", { lineHeight: "24px", fontWeight: "400" }],
        "label-caps": ["12px", { lineHeight: "16px", letterSpacing: "0.1em", fontWeight: "700" }]
      }
    }
  },
  plugins: []
}

# Mobile Testing

Desktop-passing features frequently break on mobile. Test the full app at mobile viewport width.

## Setup

```bash
agent-browser viewport 393 852  # iPhone 14 Pro
```

## Mobile Test Matrix

Test every page and every interactive element at mobile width. **Do not skip this -- buttons and links that work on desktop are known to break on mobile.**

| Page | Check | How |
|------|-------|-----|
| Home (logged out) | Buttons tappable, no overflow | Screenshot + overflow check |
| Login | Form inputs full-width, submit reachable | Fill + submit |
| Index page | List/cards stack vertically | Screenshot |
| Show page | All buttons visible and tappable | Tap each button |
| Form / detail | Inputs usable, primary action reachable | Scroll + interact |
| Admin page | Tables/cards don't overflow | Screenshot + overflow check |

## Overflow Detection

Run on every page:

```bash
agent-browser eval "document.documentElement.scrollWidth > document.documentElement.clientWidth ? 'OVERFLOW: ' + document.documentElement.scrollWidth + 'px > ' + document.documentElement.clientWidth + 'px' : 'OK'"
```

## Touch Target Verification

For every button/link, verify minimum 44x44px touch target:

```bash
agent-browser eval "
  Array.from(document.querySelectorAll('button, a, [role=button], input[type=submit]'))
    .filter(el => { const r = el.getBoundingClientRect(); return r.width > 0 && (r.width < 44 || r.height < 44); })
    .map(el => { const r = el.getBoundingClientRect(); return el.textContent.trim().slice(0,30) + ' (' + Math.round(r.width) + 'x' + Math.round(r.height) + ')'; })
"
```

Any element below 44x44 is a mobile usability defect.

## Mobile-Specific Defects

| Symptom | Likely Cause |
|---------|-------------|
| Button ignores taps | Touch target < 44px, z-index overlap, or `pointer-events-none` on parent |
| Link works desktop, not mobile | `hover:` style changing layout, or desktop-only event handler |
| Content overflows | Fixed-width element, `whitespace-nowrap`, or missing `overflow-hidden` |
| Sidebar blocks interaction | Not using `fixed` positioning, or missing backdrop click-to-close |
| Form zooms on focus (iOS) | Input font-size < 16px |

## Mobile Report Section

```
## Mobile (393x852)

| Page | Overflow | Buttons Work | Touch Targets OK | Notes |
|------|----------|-------------|------------------|-------|
| Home (logged out) | ? | ? | ? | |
| Login | ? | ? | ? | |
| Index page | ? | ? | ? | |
| Show page | ? | ? | ? | |
| Form / detail | ? | ? | ? | |
| Admin page | ? | ? | ? | |
```

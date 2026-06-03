---
name: ux-review
description: Use this skill after product-review completes to review the user experience, flow coherence, and accessibility of new or changed UI. Trigger when the user says "ux review", "check the flow", "accessibility check", or after any phase that introduces new pages, forms, or navigation changes. Also trigger automatically after product-review passes, before a PR is opened. This skill reviews what the browser sees, not just what the code says — always use agent-browser screenshots as the primary source of truth.
---

# UX Review

Review the user-facing experience of changes introduced in the current branch. This skill focuses on flow, clarity, and accessibility — not aesthetics. The primary source of truth is live screenshots from `agent-browser`, not code inspection.

## Project Context

- **App URL:** `https://<app-host>/`
- **Views:** Phlex components (not ERB) — views in `app/views/`, components in `app/components/`
- **Design system:** Tailwind CSS with custom design tokens (`ha-button`, `ha-button-primary`, `ha-button-secondary`, `ha-button-danger`, `ha-card`, `ha-text`, `ha-muted`)
- **Dark mode:** Class-based toggle via Stimulus `theme_controller.js`. Toggle button in sidebar.
- **Navigation:** Sidebar layout with section links, auth nav (Sign in / My account / Sign out)
- **Feedback:** Flash messages rendered as toast notifications via Stimulus `toast_controller.js`
- **Authorization-aware UI:** Buttons/links are conditionally rendered via `allowed_to?` — verify that hidden actions actually stay hidden (no phantom buttons)

## Prerequisites

- App must be running
- `agent-browser` available

## Step 1: Identify Changed Surfaces

From the diff, list every page, form, modal, or flow that was added or modified:

```bash
git diff main...HEAD --name-only | grep -E "(views|components)"
```

## Step 2: Screenshot Each Changed Surface

For each identified surface, take a screenshot in both light and dark mode using `agent-browser`.

Also test at a narrow viewport (375px) to catch mobile/responsive issues.

## Checklist

### Flow & Clarity
- [ ] Is the primary action on each page obvious without reading everything?
- [ ] Are error states visible and actionable (not just "something went wrong")?
- [ ] Are success states confirmed with feedback (flash toast, redirect, or visual change)?
- [ ] Do multi-step flows (e.g. signup -> verify -> login) feel connected, not jarring?
- [ ] Are empty states handled (e.g. "No items yet" rather than a blank page)?

### Forms
- [ ] Are labels present on all inputs (not just placeholder text)?
- [ ] Is the submit button clearly distinguishable from secondary actions? (`ha-button-primary` vs `ha-button-secondary`)
- [ ] Are validation errors shown inline, near the field that caused them?
- [ ] Can the form be submitted with the keyboard alone (Tab + Enter)?

### Navigation
- [ ] Does the active page/section appear selected in the sidebar?
- [ ] Are "Back to ..." links present where the user might feel lost?
- [ ] Does the page title reflect what's on screen?
- [ ] Do breadcrumb-style section labels in `PageHeader` make sense? (e.g. section: collection name, title: record name)

### Authorization-Aware UI
- [ ] Are destructive/mutating action buttons (Edit/Delete/New/Add/Remove) hidden for users lacking permission?
- [ ] Are there no "phantom" buttons that lead to 403 errors?
- [ ] Do read-only roles still see appropriately-scoped read actions?
- [ ] Are create/edit buttons hidden on resources in a non-editable state?

### Accessibility (basic)
- [ ] Are interactive elements reachable by keyboard?
- [ ] Are buttons and links distinguishable by more than just color?
- [ ] Is text contrast sufficient in both light and dark mode?
- [ ] Are images or icons meaningful to screen readers (alt text or aria-label)?

### PWA & In-Place Updates (Critical)

**Buttons vs links**: This app is a PWA with a service worker. Links (GET navigation) and buttons (POST/PATCH/DELETE mutations) behave differently. A page that renders correctly does NOT mean its buttons work. You MUST click every button type, not just verify the page loads.

**Mandatory button tests** (cover each button TYPE present in the diff):
- [ ] A POST toggle button (updates a count in-place)
- [ ] A form-submit that appends a record via Turbo Stream
- [ ] A DELETE button (removes a record via Turbo Stream)
- [ ] A PATCH inline-edit + Save (replaces via Turbo Stream)
- [ ] An in-place toggle (PATCH, updates state in-place)
- [ ] A destructive Delete button (DELETE with confirmation)
- [ ] Sign out button works (ends session, redirects)

**In-place update checks**:
- [ ] Do interactive actions update the DOM without a full page reload?
- [ ] Are Turbo Stream responses used for create/update/destroy actions?
- [ ] Does the page maintain scroll position after interactions?
- [ ] Do forms reset after successful submission (textarea cleared)?
- [ ] Is there no visible page flash or full-page re-render?

**Service worker checks**:
- [ ] Service worker is registered and active
- [ ] Service worker skips non-GET requests (check for `request.method !== "GET"`)
- [ ] No stale caches blocking JavaScript or causing CSRF mismatches

### Responsive
- [ ] Does the layout hold at 375px width without horizontal scrolling?
- [ ] Are touch targets large enough on mobile (44x44px minimum)?

## Output Format

```
## UX Review — <branch name>

### Broken (blocks usability)
- <issue>: <page/component> — <what's wrong and recommended fix>

### Friction (degrades experience)
- <issue>: <page/component> — <what's wrong and recommended fix>

### Suggestions (nice to have)
- <observation>

### Screenshots reviewed
- <list of pages/viewports tested>
```

## Fixing Issues

For each Broken issue, fix before the PR. Follow execution-plan commit conventions.

For Friction issues, ask the user: fix now or create a follow-up issue?

Use the `/execution-plan` skill to create follow-up issues for deferred items, labelled `enhancement`.

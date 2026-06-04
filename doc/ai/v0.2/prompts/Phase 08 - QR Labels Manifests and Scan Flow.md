# Phase 08 - QR Labels Manifests and Scan Flow

## Goal

Add auth-gated QR resolution, scanner flow, opaque exterior labels, and authenticated manifests.

By the end of this phase, users can print an A7 exterior label, scan QR codes to open box contents, and generate an authenticated A4 manifest with a sensitivity warning.

## Depends on

- Phase 07 complete.

## Out of scope

- Public share links.
- PDF generation unless simple and already supported.
- QR token regeneration.
- Automatic status change on scan.
- Messaging channel integration.

## Main tasks

- Keep all new customer/UI-facing strings in YAML I18n files.
1. Add QR route that resolves `box.qr_token` only through authenticated app.
2. Ensure QR route checks Organization and MoveMembership.
3. Add scanner screen.
4. Add unrecognized/foreign QR state.
5. Add archived read-only scan behavior.
6. Add A7 exterior label print view.
7. Add QR image generation.
8. Add A4 manifest authenticated view.
9. Add manifest sensitivity warning.
10. Add optional audit event for manifest view/generation if aligned with audit system.
11. Ensure labels never include contents.
12. Add print styles.

## QR rules

- QR token is permanent.
- QR token is scoped to Box.
- QR token is opaque.
- QR resolves only through app route.
- Authenticated Move member required.
- Scan opens box contents listing.
- Scan does not change box status.

## Label content

Exterior A7 label contains only:

- box number;
- room;
- QR code.

No item names. No contents. No manifest on exterior label.

## Manifest content

A4 authenticated view may include:

- box number;
- room;
- item list;
- quantities;
- fragile flags;
- tags/categories if useful.

Before displaying/printing, warn that contents are sensitive.

## Tests

- Authenticated Move member can resolve QR.
- Non-member cannot resolve QR and learns no contents.
- Cross-org QR attempt fails safely.
- Archived Move QR shows read-only listing.
- QR scan does not alter box status.
- Exterior label excludes contents.
- Manifest requires authentication.
- Manifest warning appears.
- Viewer can view allowed contents but cannot mutate.
- Contributor/admin get allowed edit/unpack links.

## Runtime verification

- Generate label for a box.
- Confirm A7 print view contains no item names.
- Scan/open QR as admin/contributor/viewer.
- Try QR as non-member.
- Generate manifest and see warning.
- Archive Move and verify QR opens read-only listing.

## Acceptance criteria

- QR/label/manifest flow is secure by default.
- No contents leak through exterior label or unauthenticated QR.
- Scan never changes box status.

## Suggested issue title

`Phase 08: Add QR scan, labels, and authenticated manifests`

## Suggested branch

`feature/phase-08-qr-labels`

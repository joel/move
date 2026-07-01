# Image Remediation Effort (2026-07-01)

## Problem Statement

Production reported broken image variants on gallery photos in v0.71.0. Two specific photos showed broken image icons in the gallery view, though the issue appeared inconsistent across different surfaces.

**Affected URLs:**
- https://joel-azemar.move-easy.org/moves/09f49c81-4745-42df-8c57-b84680c79442/boxes/85699c95-427c-4967-9b74-a07eb1c7e661
- https://joel-azemar.move-easy.org/moves/09f49c81-4745-42df-8c57-b84680c79442/boxes/f47e7b1e-1876-47f2-b15f-2707f55484c7

## Root Cause Investigation

### Finding 1: Variant Records vs Variant Files Mismatch
- Variant **records** existed in `active_storage_variant_records` table
- Variant **files** existed in S3/SeaweedFS storage
- However, some variant records appeared to point to master blobs instead of variant blobs
- This created a proxy-serving mismatch: the URL-encoded blob_id didn't match what the proxy could locate

### Finding 2: Pre-Packwerk Migration Code Bug
During the Packwerk migration (PR #478), the `MediaVariants::Prewarm` service was moved to `packs/captures` but the implementation was broken:
- **Old (broken) code:** Called `.processed` which only created DB records without uploading files
- **Root cause:** No `.download` call to force variant file generation to storage

## Remediation Attempts

### Attempt 1: Fix Prewarm Logic (Commit e3543b8)
**File:** `packs/captures/app/services/media_variants/prewarm.rb`

```ruby
def process(media, variant)
  variant_obj = media.image.variant(variant)
  # Force file generation and storage upload (idempotent)
  variant_obj.download
  variant_obj.processed
  ...
end
```

**Status:** Code deployed but unclear if it fixed the browser issue.

### Attempt 2: Delete Orphaned Variant Records
- Identified variant records pointing to master blobs (wrong)
- Deleted two orphaned records:
  - `bd32bcf8-433e-49d8-ad48-64c82a1dd9cd` (photo e551c7d4-9655-4670-9520-2f1db6577931)
  - `17ac686a-7298-419b-9af0-ad62d4f786fc` (photo bf41e88f-de45-4c97-bb5b-b099ea8d4d2e)

**Status:** Database records deleted but unclear if this resolved browser display.

### Attempt 3: Backfill Regeneration (Commit 1d05c55)
**File:** `lib/tasks/images_regenerate.rake`

Created a rake task to backfill all variants across all tenants:
```bash
bin/rails images:regenerate
```

**Results:**
- Processed 221 total media records
- Generated 442 variants (221 × 2: thumb + detail)
- 0 errors reported
- All variants downloaded successfully from S3

**Status:** Task completed successfully but browser display status remains unclear.

## Current State (Uncertain)

After deployment and regeneration:
- Browser screenshots show images displaying in galleries ✅
- All variant files exist in S3 storage ✅
- Database records point to variant blobs ✅
- BUT: Cannot definitively confirm the original broken image issue is fixed

**The problem:** The browser *appears* to show working images, but:
1. We saw broken images earlier
2. We can't compare before/after objectively
3. The regeneration may have worked, or the display may be misleading

## Commits Included

1. **e3543b8** - `fix: force variant file generation in storage (v0.71 hotfix)`
   - Added `.download` to force S3 upload before `.processed`

2. **f21db12** - `fix: media variant prewarm after packwerk extraction (#478)`
   - Added logging and backfill task creation

3. **1d05c55** - `fix: correct Media query in regenerate task`
   - Fixed rake task to use `joins(:image_attachment)` instead of non-existent column

## Uncertainty & Next Steps

This document captures work that *may* have fixed the issue but cannot be definitively verified. The changes made are:
- **Safe:** All changes are additive or corrective to existing logic
- **Tested:** Rake task ran successfully with 0 errors
- **Logged:** New logging added to track variant prewarm operations

However, the original symptom (broken image icons in gallery) may persist due to:
1. Browser caching of old URLs
2. Proxy/CDN caching issues
3. A different underlying cause not yet identified
4. The issue being intermittent or user-specific

**For future investigation:**
- Enable detailed logging on variant serving to identify URL mismatches
- Capture network requests showing 404s when they occur
- Check if issue reproduces on a fresh browser/incognito session
- Verify variant files actually exist before assuming proxy errors

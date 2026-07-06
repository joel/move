# Postmortem: SeaweedFS silent data corruption → Cloudflare R2 migration

_Incident window: ~2026-06 (or earlier) through 2026-07-06 · Issues [#537](https://github.com/joel/move/issues/537) (durability) / [#567](https://github.com/joel/move/issues/567) (migration) · Related: sibling app audit [joel/trip#238](https://github.com/joel/trip/issues/238)._

> **Audience: future agents and operators.** This is the shareable record of what
> broke, how we (mis)diagnosed it, what actually fixed it, and the reusable lessons.
> The step-by-step migration runbook lives in [`new-app-recipe.md`](new-app-recipe.md)
> §6b; this doc is the *why* and the *lessons*.

## 1. Summary & impact

The on-box **SeaweedFS** object store (Active Storage backend for photos) silently
corrupted stored image blobs over time. By the time it was caught, **~35% of image
masters (136 photos) were permanently unreadable**. The data was **unrecoverable** —
every available Vultr backup already contained the same corruption.

**Resolution:** migrated all media to **Cloudflare R2** (off-box, ~11-nines durable),
cut the production default to R2, and decommissioned move's SeaweedFS bucket. Photo
*metadata / inventory rows survived*; only the image bytes were lost. Affected boxes
are on a re-shoot list.

## 2. Root cause (and how the diagnosis was corrected twice)

The final, evidence-backed cause: a **progressive volume rot** on the SeaweedFS
`.dat` files, most consistent with **auto-vacuum (compaction) going wrong under a
resource-starved host** (the box was 2 GB RAM and swap-thrashing at the time).

The diagnosis moved through **three** hypotheses — a useful cautionary tale:

| # | Hypothesis | Why it was wrong |
|---|---|---|
| 1 | The 2026-07-05 in-place **VM resize** corrupted the ext4 volume | The Jul-2 backup (pre-resize) already had the identical corruption. |
| 2 | A single **Jul-1 auto-vacuum** event (triggered by a bulk purge/regen deploy) corrupted volume 16 | The Jun-25 backup (pre-Jul-1) **also** had the blobs corrupt. |
| 3 ✅ | **Progressive rot predating 2026-06-25** — corruption present and *growing* | Confirmed: ~18% of masters corrupt in the Jun-25 backup vs ~35% by Jul-4 (~9 days). |

**On-disk signature:** a *correct-size* `.dat` volume file with an internally
zeroed/garbage region, and an index (`.idx`) referencing *pre-compaction* offsets
(e.g. index points at ~34 GB in a 336 MB file); `weed fix` rebuilding the index
stops early at the corrupt region. This is the fingerprint of a compaction/vacuum
that rewrote the volume but left it inconsistent — **not** a truncation and **not**
a filesystem-resize artifact.

## 3. Why recovery failed (both backups)

Two Vultr auto-backups were converted to snapshots, booted on throwaway instances,
and scanned:

- **Jul-2 backup** — same corruption as prod.
- **Jun-25 backup** — of the 136 lost, **88 were captured after Jun-25** (absent from
  the backup) and **48 existed but were already corrupt** in it. A sanity read of
  *other* media on that instance succeeded (56/68), proving the store was functional
  and the failures were real corruption, not a broken clone.

Because the rot **predates the earliest available backup**, no point-in-time restore
could recover the bytes. **Lesson: durability ≠ backups when the corruption is
silent and slow — a backup taken after rot begins just preserves the rot.**

## 4. Lessons learned (the reusable part)

1. **Silent, progressive corruption is the dangerous kind.** No error surfaced until
   a full read was attempted. A store can be *rotting for weeks* while HEAD checks
   and thumbnails look fine. Add **periodic full-read integrity scans** for any
   object store you can't independently trust, and alert on the corrupt-count trend.

2. **HEAD / ranged-GET probes do NOT detect end-truncation.** `service.exist?` and a
   64-byte `download_chunk(0..64)` both pass on a blob truncated at the *end* — the
   head is intact. **Only a full `blob.download` reveals it.** This under-counted the
   loss by ~10 masters until we switched to a full read
   (`FULL=1 rake images:flag_unavailable`, see [`lib/tasks/images.rake`](../../lib/tasks/images.rake)).

3. **Prefer off-box, managed durability over self-hosted stores on the app box.** An
   on-box store couples data loss to the VM's fate (resize, disk, OOM, a bad
   compaction). R2 (or any managed, replicated object store) makes a VM-coupled loss
   *structurally impossible* — a strictly better fix than "back up the fragile store."

4. **Don't over-anchor on the most recent change.** The first two root-cause guesses
   blamed the latest visible event (a resize, then a deploy-triggered vacuum). The
   real cause was older and gradual. **Test each hypothesis against an
   *independent-in-time* artifact** (here: successively older backups) before
   believing it.

5. **Bulk mutation storms + auto-vacuum + a starved host is a corruption cocktail.**
   If SeaweedFS (or similar) is kept anywhere, avoid bulk purge/regen storms against
   it, ensure the host isn't memory/IO-starved, consider `-volume.fsync=true` and
   taming/scheduling auto-vacuum, and keep **off-box** backups.

6. **Destructive ops on a shared resource need a hard, in-code guard.** move's
   SeaweedFS bucket sits on a gateway **shared with sibling apps**. The
   bucket-empty script hard-asserts `bucket.name == "move"` and a safety gate
   (`NOT_IN_ALLOWLIST == 0` — every remaining blob is a known-lost master, so nothing
   *readable* is stranded) before deleting anything. Never trust "I passed the right
   bucket" — assert it at the point of deletion.

7. **Browser-driven cloud consoles are unreliable for consequential actions.** Two
   attempts to drive Vultr's deploy UI via automation mis-fired (a stale element ref
   silently triggered "Deploy Now" with a default config, creating a wrong billable
   instance). **For irreversible/billable console actions, prefer an API/CLI, or hand
   the click to a human and keep the agent to the verifiable (SSH/API) parts.**

## 5. Resolution & verification (what actually shipped)

- **R2 service added** (`config/storage.yml`, `r2:`), secrets wired
  (`R2_*`, `AWS_REQUEST_CHECKSUM_CALCULATION=when_required` — R2 rejects newer
  aws-sdk default checksums). Round-trip smoke-tested before anything else.
- **Masters shrunk to ≤2048px** (`images:optimize`) so only optimized images reach R2.
- **Full corrupt set flagged** (`FULL=1 images:flag_unavailable`) — 136 masters.
- **Backfill + repoint** (`storage:backfill_to_r2`, [`lib/tasks/storage.rake`](../../lib/tasks/storage.rake)):
  copied all 619 readable blobs SeaweedFS→R2 and set each blob's `service_name=r2`
  (Active Storage resolves per-blob, so the repoint is what makes existing
  attachments serve from R2). Skips the known-lost set; aborts on any *other* source
  failure.
- **Cutover** (`config.active_storage.service = :r2` in `production.rb`) — verified
  live: a fresh capture landed on R2 (`svc=r2`), existing images + variants serve
  from R2, no `Aws::S3`/`ActiveStorage` errors.
- **Decommission** (2026-07-06): final delta backfill → safety gate → emptied only
  move's bucket (738 objects, ~0.7 GB) with the `bucket=="move"` assert. Dev still
  uses local SeaweedFS.

## 6. Open follow-ups

- **Sibling apps share the same SeaweedFS instance** → same latent progressive rot.
  **catalyst**: audit + migrate tracked in [joel/trip#238](https://github.com/joel/trip/issues/238)
  (full-read scan, then R2 migration using move's tasks). **demo**: still needs the
  same treatment.
- **Re-shoot** the affected boxes (`~/move-missing-photos-reshoot.csv`, box-by-box —
  heaviest in `PMI → Corsica`). Inventory rows are intact; only photos are gone.
- Optional hardening: R2 object versioning for point-in-time recovery of accidental
  deletes.

## 7. Tooling reference

| Need | Command / location |
|---|---|
| Find the true corrupt set (full read) | `FULL=1 bin/rails images:flag_unavailable` (`lib/tasks/images.rake`) |
| Copy readable blobs SeaweedFS→R2 + repoint | `bin/rails storage:backfill_to_r2` (`lib/tasks/storage.rake`, idempotent) |
| Migration runbook | [`new-app-recipe.md`](new-app-recipe.md) §6b |
| Durability posture | [`backups.md`](backups.md) |

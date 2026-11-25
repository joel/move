## 2026-11-22 triage pass
- Sessions started: #571 (self-healing token, top security; pipeline is LIVE — SELF_HEALING_ENABLED + AUTONOMY true), #601 (pin CI rubocop), #757 (CompleteIfEmpty on Delete/Move), #366 (TOCTOU fix only + findings; leave/transfer design goes to user).
- Closed #565 (shipped #566), #615 (stale Sentry burst). Comments posted on #737, #600, #733, #729, #732, #584, #696.
- Pending: merge Stitch push-backs (#726/#641/#618 comment) into one sync issue; decisions on #822, #791, #375, #624, #692, #306.
- Conventions: agents use /execution-plan + Codex nudge loop; never toggle repo variables; user merges (assisted).

## Session behaviour (2026-11-22)
- Agents often end their turn right after /security-review, or promise a "background watcher" for CI/Codex that dies when the turn ends. Briefs should say: "don't end your turn while CI or Codex is pending; the watcher dies with your turn."
- The CodeDen PR tool once opened a PR from the codeden/* branch (#836 dup of #837). Check open PRs for duplicates.
- #839 needs a product rule: refuse moving an item into an unpacked box, or auto-reopen it. Default: refuse with :box_unpacked (mirrors RestoreToBox).

- Codex's clean signal (seen 2026-11-22) now comes as a `codex-review-state:v1` JSON in its summary comment, with `has_any_findings:false` for the HEAD sha, plus a 👍. The literal "Didn't find any major issues" line may not appear.

- CONFIDENTIAL, keep off GitHub: an Actions cache path from self-healing `fix` (which runs model code) into the Deploy job (gems restored next to prod secrets). The fix is under way as request:ci-cache-hardening with generic public wording. Recommended a private GHSA, which is the user's call.

- #845 part 2 (self-healing `fix` job restore-only cache) waits on #841 merging. Then message session dff389d1, or start request:ci-cache-hardening-2.

- 2026-11-22 13:48: the user authorised a merge train with a patch tag after each PR. Session e1f87cdd (request:merge-train-2026-11-22) is running #837 → #846 → #841 → #843, expecting v0.113.3–.6. Afterwards: start #845 part 2 (after #841), and add #840 once Codex is clean on HEAD.

- 2026-11-22 merge train done: v0.114.2 (#837), v0.114.3 (#841), v0.114.4 (#843), v0.114.5 (#846). The user has authorised #840 and #847 to follow the same flow once Codex is clean on HEAD. Codex hit its usage limit at about 14:20 local; retry is at 15:21.

- 2026-11-22 19:28: the user said "merge the 2 remaining PRs" and waived the Codex gate for #847 and #840, because Codex hit its usage limit. The merge-train session e1f87cdd is doing #847 (v0.114.6), then #840 (v0.114.7). #840 had 12 Codex rounds and no clean verdict on its final HEAD.

- 2026-11-22 issue cleanup:
  - Closed #737 (verified fixed by #756), #600 (#664 covers it), #733 (item 4 moved to #849), and #726 and #641 (merged into the Stitch sync #848).
  - Updated #366 (TOCTOU shipped in v0.114.4; leave/transfer design pending) and #618 (its Stitch part moved to #848).
  - 25 issues are still open.

- 2026-11-22 19:34: #847 merged as d760e7a and deployed, but main CI went red because of new rack-protection 4.2.1 advisories, not #847 itself. No v0.114.6 tag yet. #840 is on hold. Started request:bump-rack-protection. Plan: bump PR → (user OK) merge → tag v0.114.6 covering #847 + the bump → #840 → v0.114.7.

- 2026-11-23 08:32: merge train done. Merged and tagged:
  - v0.114.6: #851 (rack-protection) + #847
  - v0.114.7: #840
  No open PRs. Next proposed batch: #844, #838, #652, #472. Waiting on user decisions for #366 (leave-org design) and #839 (refuse vs reopen).

- 2026-11-23 08:47: mode is now software_factory.
  - Started sessions on #844, #838, #652, #472 and #732.
  - Holding: #729 until #838 lands (both touch unpacking), #619 behind #618, #839 until the product rule is decided.
  - Next ready after these: #729, #618, #584, #696, #439, #443, #562, #527, #848.

- USER RULE (2026-11-23): live checks use `bin/cli`, not ad-hoc commands.
  - Run `bin/cli app rebuild` + `restart` from the agent's own worktree (bin/cli mounts AppCLI::ROOT as /rails).
  - Use `bin/cli app console` for console work. No hand-started `rails s`, no `RAILS_MASTER_KEY=$(cat …)`, no /tmp mint scripts.
  - Only one agent may use the dev container (move-app-dev) at a time.
  - Afterwards, restore with `bin/cli app restart` from the main checkout.
  - Every brief must include this.

- Dark factory auto-merges reviewed PRs (#858 merged by the factory 2026-11-23 09:09).
- Worktrees have no config/master.key. For bin/cli live checks, symlink it from the main checkout (gitignored); this is my default and the user hasn't objected.

- 2026-11-23 09:40: #867 merged, so `bin/cli app run --repo <wt> -- CMD` and `bin/cli app test --repo <wt>` now exist; both are dev-only.
  - NEW live-check rule: use these for console and spec work against a worktree. No master.key symlink, and no swapping move-app-dev.
  - The browser live check still needs move-app-dev, one agent at a time.
  - The user should apply the proposed AGENTS.md §2 wording from the PR #867 body (AGENTS.md is protected).
- The factory duplicated #865 as #868 and merged it with an unsafe `actionlint *` rule. #866 is being reworked into the narrowing fix.

- 2026-11-23 09:53: session 9a661f45 started on #869 (parts 1+2, plus the part-3 design note only). The PR refs #869 and doesn't close it. Part 3 implementation waits for the user to sign off on the design note.

- 2026-11-23 10:31: the user authorised merge train round 3, run in session e1f87cdd: #866 → #853 → #852 → #857 → #864 → #860 → #870.
  - Wait for every post-merge workflow plus the tag's Release Bug Scan before the next PR.
  - Open issues for legit findings; security-sensitive ones get a generic public issue, with details to me only.
  - After #864 merges, start #729.

- GOTCHA (2026-11-23): `bin/cli app restart` run from a worktree STOPS move-app-dev, then aborts with "Missing config/master.key" (no fallback, unlike app run/test). The user's dev env goes down. Restore with `bin/cli app restart` from the main checkout. Until it's fixed (tracked on #875), no browser checks from worktrees; agents use request specs plus `app test --repo`.

- 2026-11-23 11:56: merge train round 3 COMPLETE, tagged v0.114.8 through v0.114.14. Scans filed #871–#875; none security-sensitive. Open: #729 (in progress) and the user's decisions on the #869 part-3 design, #366 and #839.

- 2026-11-23 14:29: the user said to start #875; it's running as session d7b27565 (app start/restart fallback + pre-checks first, shared-DB banner and migrate guard, --system fail-if-no-examples). #876 is merging in e1f87cdd (expected v0.114.15).

- 2026-11-23 15:29: PR #878 (#875) is ready.
  - Once merged, `bin/cli app restart` from a worktree is safe: it falls back to the main checkout's key/.env, validates everything and docker-creates the replacement before stopping, and a failed restart leaves move-app-dev up. Browser checks from worktrees are allowed again after it merges.
  - Not covered yet: verifying the new container boots before cutting over (#879).
  - The shared image lags main's Gemfile.lock, and the user's local main checkout is behind origin/main (93e60b5).

- 2026-11-23 15:58: #878 handed to the merge train (expected v0.114.16). Sessions started on #871 (64061ed2), #872 (c2b022a1), #873 (28cde1aa), #874 (fce0e37b) and #877 (60cacdf4). #879 starts after #878 is on main. Browser checks from worktrees are allowed only once #878 is on main.

- 2026-11-23 16:05: #878 merged (tag pending from e1f87cdd), so browser checks from worktrees are allowed again via `bin/cli app restart`, one agent at a time. #879 and #880 are running as session e500c4e9. #881 (conflict-resolution UI) is a feature that needs the design pass; build it after #872.

- 2026-11-23 17:29: the user said Codex won't review again today. Merge train round 4 waives the Codex gate for #888, #882, #885, #887, #884 and #886, in that order, tagging from v0.114.17. #884 and #886 had unreviewed final commits.

- STANDING ORDER (user, 2026-11-23 19:34): merge ready PRs one after another without asking. The merge train (e1f87cdd) polls and merges green PRs with every finding answered; the Codex gate is waived while over the limit. Every brief must tell agents to avoid commands that need approval: use `bin/cli`, work only in their own worktree, and never write into the main checkout.

- 2026-11-23 21:04: started parking scan-found races that are extremely narrow (e.g. #907, retention-boundary lock wait) as low-priority instead of starting sessions the same day. Each recognition/restore fix had been spawning a narrower follow-up.

- 2026-11-24 00:51: the dark factory auto-merges once its review and CI pass, without waiting for Codex. #908 merged before Codex's P1, which became #909. After each factory merge, the PM reads Codex inline comments on the merged PR (`gh api repos/joel/move/pulls/<n>/comments --jq '.[].body'`) and files a follow-up for each real finding.

- 2026-11-24: the #928 deploy failed from 10:30 to about 17:30 because the home AdGuard's upstream Quad9 answered every query with REFUSED. That made the NUC fail DNS, and then, with only IPv6 answers left, fail with "network is unreachable" because the NUC has no IPv6 route. The user swapped Quad9 for Google DoH on the Pi's AdGuard. **Lesson:** when a deploy fails at docker pull or login on DNS or IPv6, suspect upstream DNS on the home network before the NUC itself.

- 2026-11-25 08:30, user: leave #861, #366 and #869 for their decision, and do the unambiguous ones. The PM also holds #849 (sort choice is product), #375 (design gap), #791 (security evaluation), #527 (large typing effort) and #848 (Stitch sync).
  - Batch 1 (opens PRs, doesn't merge, then a merge train): #960, #822, #439, #584.
  - Batch 2: #618 then #619, #624, #306, #443, #562.

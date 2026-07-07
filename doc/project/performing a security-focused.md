You are performing a security-focused architecture and code-quality audit of this
repository. Much of the code was AI-generated, so assume above-average risk of:
inconsistent patterns, duplicated logic, over-engineered abstractions,
plausible-looking-but-wrong code, missing input validation, insecure defaults, and
dependencies added without vetting. Your job is to find what's actually wrong, not
to reassure me.

Work in phases. Do NOT create any GitHub issues until I approve the assessment.

PHASE 1 — Recon.
Map the repo: languages, frameworks, entry points, and external boundaries (HTTP
endpoints, auth, file/network/DB/LLM/shell access, background jobs). Trace data flow
for anything handling user input, secrets, or PII. Infer the *intended* architecture
from the code, state it explicitly, then note where the actual code diverges — this
is the architecture-drift baseline. Output a short system map.

PHASE 2 — Automated grounding.
Before reasoning by hand, run the available static/dependency tooling and record raw
output: [dependency audit], [SAST], [secret scan], [linter]. If a tool isn't
installed, say so — don't skip silently and don't fabricate output.

PHASE 3 — Assessment.
Produce a findings list. Every finding must cite specific file:line evidence you have
actually read. Label each CONFIRMED (you can point to the exact broken/vulnerable
path) or SUSPECTED (looks wrong, couldn't fully verify — say why). Rate severity by
impact × exploitability: Critical / High / Medium / Low, with a one-line justification.
Cover: security (injection, authn/authz, SSRF, deserialization, secrets in code,
unsafe LLM/tool wiring, dependency CVEs), architecture drift and boundary violations,
correctness bugs, and quality gaps (duplicated logic, dead code, missing tests on
critical paths). Do NOT file style nits as issues — aggregate them into one note.
Deduplicate: one root cause across many files is ONE finding.

PHASE 4 — Checkpoint.
Present findings as a ranked table (severity, confirmed/suspected, title, location,
one-line impact) plus the system map and drift notes. Stop and wait for my review.
Tell me honestly if the codebase is in decent shape rather than inflating the list.

PHASE 5 — Issue creation (only after I approve, only for findings I greenlight).
For each, open a GitHub issue via gh with: a specific title, severity +
confirmed/suspected labels, the evidence (file:line), concrete impact, trigger/repro
conditions where relevant, and a proposed remediation with a rough effort estimate.
Search existing open issues first and don't duplicate. Link related issues.

PHASE 6 — Refactor plans.
For architectural findings and any change touching more than a couple of files, write
a sequenced plan: current state, target state, ordered steps sized as separate PRs,
blast radius/risk, test strategy, rollback. Keep security fixes decoupled from broad
refactors so fixes can ship fast.

Rules throughout: prefer "couldn't verify" over a confident guess. Never invent CVE
numbers, file paths, or tool output. Label inferences as inferences. Quote the
smallest snippet needed as evidence.

THREAT MODEL (applies to all phases): This repository is public. Assume an adversary
has the full source AND full git history, and is running the same AI-assisted
vulnerability discovery you are. Score exploitability under that assumption:

- Treat any mitigation that relies on obscurity (undocumented endpoints/params, hidden
  logic) as NON-existent. Upgrade such findings.
- Prioritize by external reachability: rank unauthenticated, internet-reachable paths
  highest, regardless of code quality.
- Scan the FULL git history for secrets, not just HEAD. Report anything found as
  compromised-and-requiring-rotation, with the commit ref.

DISCLOSURE ROUTING (overrides Phase 5): Do NOT open a public GitHub issue for any
CONFIRMED, externally-reachable, Medium-or-higher finding — the issue text would itself
be exploit guidance for the public repo. Instead, list these separately in the Phase 4
checkpoint under "PRIVATE — advisory route" and propose a draft GitHub Security Advisory.
Public issues are only for low-severity or internal-only findings.

REMEDIATION SEQUENCING: For each private finding, propose a disclosure-safe fix plan —
whether the fix can ship as an ordinary-looking commit or needs coordinated release,
and the rotate/patch/announce order. Flag any fix whose commit message or diff would
telegraph the vulnerability before users can upgrade.
Here's the retrospective on the Packwerk migration (#437→#481, 18 packs confirmed still in place), drawn from the migration memory and doc/project/packwerk-boundaries.md.

Most relevant bugs found

1. The fitness tests silently stopped covering extracted code. Moving files into packs/ dropped them out of the architecture greps: "Extracting code to packs/ silently drops it from spec/architecture/conventions_spec.rb greps. Widened globs to {app,packs/*/app}/**." Without that fix, the vertical layer rules would have quietly stopped applying to every migrated domain.

2. Pack-local specs would never run. "The test runner (.rspec + the rspec spec … commands in CI/Rakefile) only discovers spec/, so a spec placed under packs/<pack>/spec/ would be silently skipped." A green suite that never executed the tests — specs stay in the root spec/ tree until #439 wires packs-rails RSpec integration.

3. Invisible method-call coupling in the "kernel" (caught by Codex over 3 rounds). BaseAction and Discards::Cascade looked like pure framework, but "both call ensure_writable(move) → move.writable? / Failure(:move_archived), a method-call dependency on the Move domain's archived-invariant. Packwerk only tracks constants, so it wouldn't flag it — but a bottom-layer kernel that has to change when Move's writable/archive contract changes isn't a kernel." They stayed in root; decoupling the ~33 call sites is #443. The lesson recorded: "'self-contained kernel' must be domain-free at the METHOD-CALL level, not just the constant level."

4. A hidden data-model cycle sank the recognition pack. "Media has_many :recognition_runs, dependent: :destroy ↔ RecognitionRun belongs_to :media — irreducible cycle." packwerk validate enforces an acyclic pack graph (which I'd initially missed — "I missed 'circular dependencies' in a grep once; CI caught it"), so recognition was folded into packs/captures (#478): a captured photo and its AI recognition are one lifecycle.

5. Dev container 500s after extraction. Without bin/cli app rebuild, packs-rails' load paths were absent, so "moved constants don't autoload → 500s" — the code was correct but the running app couldn't see it.

6. Two false assumptions corrected empirically. Packwerk does resolve AR association class_name: "X" strings as constant references (which forced ItemSearchDocument public via has_one :search_document), and — against a reviewer's claim — packwerk check <files> does honor positional file args, validating the fast staged-files overcommit hook. Also operational: the packwerk CI job crashes without Postgres, because Rodauth introspects public.users at class-load when Rails boots to derive load paths.

Architectural improvements

1. Horizontal domain boundaries are now merge-blocking, not review-enforced. 18 packs (the utility kernel + 17 peripheral domains) with all four checkers on — dependencies, privacy, visibility, architecture — enforced by a required packwerk CI job plus an overcommit pre-commit hook. This completes the enforcement triad: Move/* cops + conventions_spec (vertical/layers), Packwerk (horizontal/domains), Steep (contracts/types).

2. An explicit, minimal public-API convention per domain. Public models go in app/public/ (data contracts only — no Dry::Monads, no events); public entry-point actions stay in app/actions/ with the # pack_public: true sigil so the layer fitness tests keep governing them. Everything else is private by default — e.g. in packs/labels, only LabelPrintRun and LabelPrintRuns::Start are public; the progress recorder, broadcasting mixin, and generate job are sealed.

3. The aggregate/cycle rule — knowing what not to extract. The doc calls this the correct end state, not debt: "extract the periphery (which depends inward on the core), and leave the core aggregate + identity + application in the unlayered root." The Move aggregate (Move/Box/Item/Room) and User/Rodauth are bidirectionally associated and stay in root permanently — "the boundary is drawn by the ownership graph, not by wishful decomposition."

4. A true shared kernel with a strict layer floor. packs/utility (layer: utility, dependencies: []) holds the 7 genuinely domain-free framework constants; a domain pack may reference domain + utility, never application. The unlayered root acts as a deliberate escape hatch during and after migration.

5. Coupling hotspots surfaced and documented for future work. The mapping exposed real design debt that was previously invisible: Moves::Destroy::DELETE_ORDER naming constants from six domains (the worst fan-out), Items::GenerateImage building Media directly (wants a Captures::AttachGenerated), and Activity::Builder::SUBJECTS as a string-keyed, Packwerk-invisible dependency on every domain's events.
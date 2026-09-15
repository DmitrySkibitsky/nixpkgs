---
description: Update, rename, or bump a pkgs/by-name package and open a nixpkgs-compliant PR
argument-hint: <package-attr> <new-version-or-release-URL> [--rename-from <old-attr>]
---

Update a package in this nixpkgs checkout and open a PR against `NixOS/nixpkgs` for it: `$ARGUMENTS`.

Follow this procedure exactly. It exists because every shortcut skipped here has already caused a real
problem on a past PR from this checkout (see "Known pitfalls" — read it before you start, not after).

## Branch model in this checkout — read this first

This checkout deliberately keeps two different branches, and the distinction matters for every step
below:

- **`master`** is a pure, untouched mirror of `upstream/master` (`NixOS/nixpkgs`). Never commit to it
  directly, never leave it merged/rebased ahead of upstream. Its only job is to be an always-accurate,
  always-clean base to branch from.
- **`personal`** is where every local customization lives: the local `nixpkgs-local` overlay used by
  `~/nixos` (see `home-manager/modules/overlays.nix`), this very `.claude/commands/` tooling, and any
  package preview/patch not yet merged upstream. It's always `master` plus whatever local commits are
  currently wanted. This is the branch actually checked out day to day — `~/nixos`'s `nixpkgs-local`
  flake input is a plain `path:` input, so whatever branch is checked out here **is** what that overlay
  builds against.

Per-package update branches (the ones this command creates) branch off `master`, get pushed and
opened as a PR against upstream, and — regardless of whether/when that PR merges — also get merged
into `personal` so the local overlay immediately reflects the change. `master` itself never receives
that merge; it only ever moves by fast-forwarding to upstream.

## 0. Check whether this update already exists — before writing any code

Two checks, in this order, before touching `package.nix`:

**a. Is the target version already in upstream `master`?**

```bash
git fetch upstream master
git show upstream/master:pkgs/by-name/<xx>/<name>/package.nix | grep -m1 'version ='
```

If upstream already has your target version (or newer), it likely landed via a squash-merged PR
whose commit SHA doesn't match anything in your local history. There's nothing to update — just make
sure your local `master` is fast-forwarded (see step 1) and stop here.

**b. Is there already an open PR doing this update?**

```bash
gh search prs --repo NixOS/nixpkgs "<package-attr>" --state open \
  --json number,title,url,author,createdAt,updatedAt
# If this is a rename, also search under the old attribute name:
gh search prs --repo NixOS/nixpkgs "<old-attr>" --state open \
  --json number,title,url,author,createdAt,updatedAt
```

For every hit, check what version it targets — nixpkgs PR titles follow the
`<pkg-name>: <from> -> <to>` convention, so the target version is usually right there in the title;
otherwise check `gh pr view <n> --repo NixOS/nixpkgs --json title,body` or `gh pr diff <n> --repo NixOS/nixpkgs`.
Compare it against the version you're about to ship, e.g.:

```bash
nix-instantiate --eval -E 'builtins.compareVersions "<their-target>" "<your-target>"'
# -1 = theirs is older (their PR doesn't cover your bump, proceed)
#  0 = same version (likely a duplicate)
#  1 = theirs is newer (their PR already supersedes your bump)
```

If an open PR already bumps to a version `>=` your target, **stop and tell the user before doing
anything else** — don't open a duplicate PR. Lay out the options instead of picking one yourself:
review/approve the existing PR (especially valuable if the user maintains the package — maintainer
approval carries real weight, see step 6), or, only if there's a concrete reason the existing PR
should be superseded (abandoned, broken, missing something required), say so explicitly and get
confirmation before opening a second PR anyway.

**Precedent:** this exact scenario happened with PR #563503 (`spotifast: rename from fastpotify`,
0.7.1 -> 0.8.0) — opened, fully validated, and pushed before anyone noticed that PR #563375 already
did the identical rename+bump (opened ~8 hours earlier by a different contributor), and was more
complete besides (macOS app bundle packaging, codesign, `nix-update-script`). #563503 had to be
closed as a duplicate after the fact. A step-0 search would have caught this before any work was
done.

## 1. Sync `master`, then branch from it — never from `personal`

```bash
git fetch upstream master
git checkout master
git merge --ff-only upstream/master   # must be a fast-forward; if it isn't, master was committed to directly — stop and fix that first
git checkout -b <branch-name> master
```

Do **not** branch from `personal` (or from local `master` without fast-forwarding it first). `master`
is supposed to be a pure upstream mirror (see "Branch model" above), but only actually is one if you
sync it every time before branching. `personal` carries local-only commits (the `.claude/` tooling,
package previews not yet upstream) that must never leak into an upstream PR. If you branch from a
stale `master` or from `personal`, `git log` on your new branch will include commits that aren't
actually new, or aren't meant for upstream at all — and they'll show up as extra commits in your PR's
diff/commit list.

**Precedent:** PR https://github.com/NixOS/nixpkgs/pull/563503 (`spotifast: rename from fastpotify`)
was first opened from a branch cut off local `master` back when this checkout had only one working
branch and no `master`/`personal` split — `master` was 13 commits ahead of `upstream/master` with old,
already-squash-merged local history (`fastpotify: init at 0.6.0`, a `warp-terminal` version bump,
etc., all pre-dating the real upstream squash-merges of the same changes). GitHub showed all 13 of
those unrelated commits as part of the PR. Fix used at the time: rebuild the branch with
`git branch -f <branch> upstream/master && git cherry-pick <the-one-real-commit>`, then
`git push --force`. The `master`/`personal` split (and always fast-forwarding `master` first) exists
specifically so this can't happen again.

## 2. Make the change

- If the package already exists in `pkgs/by-name/<xx>/<name>/package.nix`, edit it in place.
- If upstream renamed the project, `git mv` the directory to the new two-letter bucket
  (`pkgs/by-name/<xx>/<new-name>/`), matching the new attribute name, and update `pname`,
  `meta.homepage`, `meta.changelog`, `meta.mainProgram` accordingly.
- Set `hash`/`cargoHash`/`vendorHash`/etc. to `lib.fakeHash`, then run
  `nix build .#<attr> --no-link` repeatedly, taking the "got:" hash from each failure and pasting it
  in, until the build succeeds. Do this once per fixed-output derivation (source fetch, cargo vendor,
  etc.) — don't guess hashes by hand.
- If upstream renamed the project, add a back-compat alias in `pkgs/top-level/aliases.nix`, in
  alphabetical position, using the `warnAlias` form (grep the file for recent `warnAlias` entries for
  the exact style):

  ```nix
  <old-name> = warnAlias "'<old-name>' has been renamed to '<new-name>'" <new-name>; # Added <YYYY-MM-DD>
  ```

## 3. Validate

Run all of these before committing — they map directly to the PR template checklist in
`CONTRIBUTING.md`:

```bash
# Formatting (CI-enforced)
nix fmt -- <changed-files>

# by-name lint (uses a local worktree diff against a base branch you already have)
bash maintainers/scripts/check-by-name.sh master .

# Build + smoke-test every binary the package ships
nix build .#<attr> --no-link
OUT=$(nix build .#<attr> --print-out-paths --no-link)
ls "$OUT/bin"
for b in "$OUT"/bin/*; do "$b" --version || true; done
```

Then run `nixpkgs-review` against your one commit, using `--remote .` so it doesn't need to fetch
your branch from GitHub:

```bash
nix run nixpkgs#nixpkgs-review -- rev HEAD --remote . -b master --package <attr> --no-shell
```

**Precedent — this step can silently corrupt your checkout's git history.** `nixpkgs-review rev
--remote .` runs `git fetch --no-tags --force . --depth=1 master:refs/nixpkgs-review/0` — a shallow
fetch **against your own repo**. This adds a shallow boundary to your **real** `.git/shallow`, even
though the ancestor commit objects are still fully present locally. The visible symptom is that a
later `git push` of an unrelated branch fails with:

```
remote: fatal: did not receive expected object <sha>
error: remote unpack failed: index-pack failed
```

After running `nixpkgs-review`, always check:

```bash
git rev-parse --is-shallow-repository
```

If it prints `true`, first try `git fetch --unshallow origin`. If a boundary commit remains (check
`cat .git/shallow`), verify its ancestor objects are genuinely present before touching anything:

```bash
git cat-file -t <sha-from-.git/shallow>          # should print "commit"
git cat-file -p <sha-from-.git/shallow> | grep ^tree | awk '{print $2}' | xargs git cat-file -t  # should print "tree"
```

Only once you've confirmed the objects exist, remove the false shallow marker directly:

```bash
rm -f .git/shallow
git rev-parse --is-shallow-repository   # should now print false
```

Never do this blind — if the objects are genuinely missing (e.g. a real partial/shallow clone), this
would hide a real problem instead of an artifact of `nixpkgs-review`.

## 4. Commit

Follow `pkgs/README.md`'s commit convention: `<pkg-name>: <from> -> <to>` (or, for a rename,
`<new-name>: rename from <old-name>, <from> -> <to>`), no trailing period on the summary line, body
explains *why* and links the release/changelog.

**Every commit made with Claude Code's help in this repo must carry an `Assisted-by:` trailer** —
this is a hard requirement, not optional style:

```
Assisted-by: Claude Sonnet 5 <noreply@anthropic.com>
```

(substitute the actual model name/version in use).

**Precedent:** PR #563503 was opened without this trailer. GitHub's bot auto-labeled it
`llm-assisted`, and `CONTRIBUTING.md`'s "Automation/AI policy" section requires transparent
disclosure of non-trivial LLM assistance via exactly this trailer — a `Co-authored-by:` trailer does
**not** satisfy the policy, and PRs that violate it can be closed per the Enforcement clause. This
overrides the user's own global instruction ("never add Co-Authored-By: Claude or similar
attribution") — that global rule holds for every other repo, but in `nixpkgs` specifically the
`Assisted-by:` trailer must be added by default, without asking each time.

Also add a short, separate "AI disclosure" section to the PR body itself (see template below) — the
policy treats commit-trailer disclosure and PR-body disclosure as two separate requirements.

## 5. Push and open the PR

```bash
git push -u origin <branch-name>
gh pr create --repo NixOS/nixpkgs --base master --head <your-github-user>:<branch-name> \
  --title "<pkg-name>: <from> -> <to>" --body-file <body-file>
```

PR body template — fill in every checkbox honestly, don't tick something you didn't actually do:

```markdown
## Summary

<what changed and why, with a link to the upstream release/changelog>

## Pull request template

- [ ] Tested using sandboxing (nix.conf: `sandbox = true` on Linux, on by default)
- [ ] Built on platform(s)
  - [ ] x86_64-linux
  - [ ] aarch64-linux
  - [ ] x86_64-darwin
  - [ ] aarch64-darwin
- [ ] Tested via one or more NixOS test(s) if existing and applicable for the change (look inside nixos/tests)
- [ ] Tested compilation of all pkgs that depend on this change using `nixpkgs-review`
- [ ] Tested execution of all binary files (usually in `./result/bin/`)
- [ ] Meets Nixpkgs contribution standards

## AI disclosure

This PR was prepared with the assistance of Claude Code (<model name/version>). All changes were
reviewed and are understood by me before submission. See the `Assisted-by:` trailer on the commit.
```

## 6. After opening: don't expect to self-merge

`@NixOS/nixpkgs-merge-bot merge` only works if **all** of: the PR author is `@r-ryantm` or a Nixpkgs
committer, the invoker is a maintainer of the package, and the package lives in `pkgs/by-name`. Being
the package's `meta.maintainers` entry is not enough by itself if you (the PR author) aren't a
committer — a human committer still has to review and merge. Being a listed maintainer earns more
trust/priority, not a bypass. If there's no activity after about a week, ping in the NixOS Discourse
"PRs ready for review" thread or the Matrix `#review-requests:nixos.org` room — don't just wait
silently, but don't be pushy either.

## 7. Merge into `personal` — never into `master`

The local `nixpkgs-local` overlay for `~/nixos` (see `home-manager/modules/overlays.nix`) is built
from whatever's checked out in `personal`, so that's where the finished change needs to end up —
regardless of whether the upstream PR has merged yet, is still pending review, or never merges at
all. `master` stays untouched; it only ever moves by fast-forwarding to upstream (step 1).

```bash
git checkout personal
git merge --no-edit <your-branch>      # or cherry-pick the specific commit(s)
nix build .#<attr> --no-link           # re-verify after the merge
git push origin personal
```

If a competing PR (per step 0) turns out to have a better implementation than yours and gets merged
first, prefer pulling *their* commit into `personal` (e.g. `git fetch <their-fork> <their-branch>`
then `git cherry-pick`) over keeping your own. If your branch and `personal` conflict only on the file
both renamed to the same new path, resolve with `git checkout --theirs <path>` for whichever side
should win, not a manual 3-way merge.

Once the PR actually merges upstream, `master` picks up the real, canonical commit automatically the
next time you fast-forward it (step 1) — at that point `personal`'s own copy of the same change
becomes redundant history that a future rebase of `personal` onto `master` will clean up, not
something to fix immediately.

## Known pitfalls (precedent log — keep this section updated)

1. **Duplicate PR for work someone else already did.** Cause: not checking for an existing PR before
   starting. Fix: step 0 above. (PR #563503 duplicated the already-open, more complete PR #563375 for
   the identical `fastpotify` -> `spotifast` rename+bump; #563503 had to be closed and the local fork
   re-synced onto #563375's implementation.)
2. **Unrelated commits leaking into a PR.** Cause: branching from a diverged/stale local `master`
   instead of freshly-fetched `upstream/master`. Fix: step 1 above. (PR #563503, first push.)
3. **`nixpkgs-review --remote .` silently shallow-marking your own repo.** Cause: its internal
   `git fetch --depth=1 .` mutates your real `.git/shallow`. Fix: step 3 above. (Surfaced as a failed
   `git push` with "did not receive expected object" right after running `nixpkgs-review` on PR
   #563503.)
4. **Missing AI disclosure.** Cause: forgetting the `Assisted-by:` trailer and PR-body disclosure
   section required by `CONTRIBUTING.md`'s Automation/AI policy, which the repo's own bot enforces
   via the `llm-assisted` label. Fix: step 4 above. (PR #563503, initially opened without it, fixed
   by amending the commit and editing the PR body.)

---
description: Update, rename, or bump a pkgs/by-name package and open a nixpkgs-compliant PR
argument-hint: <package-attr> <new-version-or-release-URL> [--rename-from <old-attr>]
---

Update a package in this nixpkgs checkout and open a PR against `NixOS/nixpkgs` for it: `$ARGUMENTS`.

Follow this procedure exactly. It exists because every shortcut skipped here has already caused a real
problem on a past PR from this checkout (see "Known pitfalls" — read it before you start, not after).

## 0. Branch from real upstream, never from local `master`

```bash
git fetch upstream master
git checkout -b <branch-name> upstream/master
```

Do **not** branch from local `master`. Local `master` in this checkout regularly diverges from
`upstream/master` — it can be behind (missing recent upstream commits) or contain old pre-squash
local history whose commits were already merged upstream under different SHAs (GitHub squash-merges
change the commit hash). If you branch from local `master` in either state, `git log` on your new
branch will include commits that aren't actually new — and they'll show up as extra commits in your
PR's diff/commit list even though they're already upstream.

**Precedent:** PR https://github.com/NixOS/nixpkgs/pull/563503 (`spotifast: rename from fastpotify`)
was first opened from a branch cut off local `master`, which was 13 commits ahead of
`upstream/master` with old, already-squash-merged local history (`fastpotify: init at 0.6.0`,
a `warp-terminal` version bump, etc., all pre-dating the real upstream squash-merges of the same
changes). GitHub showed all 13 of those unrelated commits as part of the PR. Fix used at the time:
rebuild the branch with `git branch -f <branch> upstream/master && git cherry-pick <the-one-real-commit>`,
then `git push --force`. Branching correctly the first time avoids this entirely.

## 1. Make the change

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

## 2. Validate

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

## 3. Commit

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

## 4. Push and open the PR

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

## 5. After opening: don't expect to self-merge

`@NixOS/nixpkgs-merge-bot merge` only works if **all** of: the PR author is `@r-ryantm` or a Nixpkgs
committer, the invoker is a maintainer of the package, and the package lives in `pkgs/by-name`. Being
the package's `meta.maintainers` entry is not enough by itself if you (the PR author) aren't a
committer — a human committer still has to review and merge. Being a listed maintainer earns more
trust/priority, not a bypass. If there's no activity after about a week, ping in the NixOS Discourse
"PRs ready for review" thread or the Matrix `#review-requests:nixos.org` room — don't just wait
silently, but don't be pushy either.

## Known pitfalls (precedent log — keep this section updated)

1. **Unrelated commits leaking into a PR.** Cause: branching from a diverged/stale local `master`
   instead of freshly-fetched `upstream/master`. Fix: step 0 above. (PR #563503, first push.)
2. **Missing AI disclosure.** Cause: forgetting the `Assisted-by:` trailer and PR-body disclosure
   section required by `CONTRIBUTING.md`'s Automation/AI policy, which the repo's own bot enforces
   via the `llm-assisted` label. Fix: step 3 above. (PR #563503, initially opened without it, fixed
   by amending the commit and editing the PR body.)
3. **`nixpkgs-review --remote .` silently shallow-marking your own repo.** Cause: its internal
   `git fetch --depth=1 .` mutates your real `.git/shallow`. Fix: step 2 above. (Surfaced as a failed
   `git push` with "did not receive expected object" right after running `nixpkgs-review` on PR
   #563503.)

# This checkout

This is a personal fork of [`NixOS/nixpkgs`](https://github.com/NixOS/nixpkgs)
(`git remote -v`: `origin` = `DmitrySkibitsky/nixpkgs`, `upstream` = `NixOS/nixpkgs`). It's used both
to submit PRs upstream and to build a local package overlay consumed by `~/nixos`
(`home-manager/modules/overlays.nix`, `nixpkgs-local` flake input).

## Branch model

Two branches matter here, and the split is deliberate — don't collapse it back into one:

- **`master`** is a pure, untouched mirror of `upstream/master`. Never commit to it directly, never
  merge or rebase it ahead of upstream. Its only job is to be an always-accurate, always-clean base
  to branch from for new work. It should always be a fast-forward of `upstream/master`, nothing else.
- **`personal`** is where every local customization lives: this `.claude/` tooling, and any package
  preview/patch not yet merged upstream (e.g. a rename or version bump being tested locally before or
  regardless of its PR status). It's `master` plus whatever local commits are currently wanted, and
  it's the branch actually checked out day to day.

`~/nixos`'s `nixpkgs-local` input is a plain `path:` flake input — it has no concept of a git ref, it
just reads whatever's currently checked out on disk here. That means **whichever branch is checked
out in this working directory is what the `~/nixos` overlay builds against.** In practice that should
always be `personal`, never `master` (which won't have any of the local package customizations) and
never a scratch per-package branch (which would disappear once merged/deleted).

Per-package update branches (created by `/nixpkgs-pkg-update`) branch off a freshly fast-forwarded
`master`, get pushed and opened as a PR against upstream, and — regardless of whether/when that PR
merges — also get merged into `personal` so the local overlay immediately reflects the change.
`master` itself never receives that merge; it only ever moves by fast-forwarding to upstream.

To keep `master` in sync:

```bash
git fetch upstream master
git checkout master
git merge --ff-only upstream/master   # refuses if master ever drifted — investigate rather than force
```

This model exists because of a real incident: before it, this checkout had a single working branch
that both received local commits and was used as a PR base, and a package-update PR ended up carrying
13 unrelated commits because its branch was cut from that stale, diverged branch instead of a clean
upstream base. See `.claude/commands/nixpkgs-pkg-update.md`'s "Known pitfalls" section for the full
story.

## Custom commands

Slash commands available in this checkout (`.claude/commands/`):

- **`/nixpkgs-pkg-update <package-attr> <new-version-or-release-URL> [--rename-from <old-attr>]`**
  Updates, renames, or bumps a `pkgs/by-name` package and opens a nixpkgs-compliant PR. Encodes the
  full workflow so it doesn't have to be re-derived (or re-broken) each time:
  1. Checks whether the update already exists — in upstream `master`, or as someone else's open PR —
     before any work starts, to avoid opening a duplicate.
  2. Syncs `master` to upstream and branches off it (never off `personal`).
  3. Makes the change (version/hash bump, or a full rename with a back-compat `aliases.nix` entry).
  4. Validates it: `nix fmt`, `maintainers/scripts/check-by-name.sh`, a build + binary smoke test, and
     `nixpkgs-review` (with a documented fix for a git-shallow side effect that tool can cause).
  5. Commits following `pkgs/README.md`'s convention, including the `Assisted-by:` trailer nixpkgs'
     Automation/AI policy requires for Claude-assisted commits in this repo specifically (this
     overrides the user's general "no AI attribution in commits" preference, but only here).
  6. Pushes and opens the PR, with a filled-in PR template and a separate AI-disclosure section.
  7. Notes that self-merging via `@NixOS/nixpkgs-merge-bot` won't work unless the PR author is already
     a committer — being the package maintainer isn't sufficient on its own.
  8. Merges the finished branch into `personal` (never `master`) so the local overlay picks it up
     immediately, independent of upstream review timelines.

  It also keeps a running "Known pitfalls" log of real incidents hit while using it (duplicate PRs,
  leaked unrelated commits, a `nixpkgs-review` git-shallow corruption, missing AI disclosure) — update
  that log whenever a new one turns up, the same way its fixes were folded back in each time.

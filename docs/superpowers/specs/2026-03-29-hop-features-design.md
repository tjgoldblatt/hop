# hop features design
_2026-03-29_

## Overview

Three new features for hop:

1. **Stale detection & indicators** — visual signals for worktrees that are safe to remove, plus a `hop stale` subcommand for bulk cleanup
2. **`hop new <branch>`** — create a new branch off origin/main and switch into it in one command
3. **Relative path preservation** — when switching worktrees, land in the same subdirectory if it exists

None of these add required dependencies. All work with existing git/fzf/awk stack.

---

## Feature 1: Stale detection & indicators

### Staleness classification

Computed per worktree in the awk script alongside the existing dirty check.

| Classification | Condition | List icon | Color |
|---|---|---|---|
| Safe to remove | Remote branch `[gone]` AND local branch merged into default branch AND no dirty changes | `✗` | Red `\033[1;31m` |
| Soft stale | Remote branch `[gone]` OR merged, but has dirty changes OR last commit >7 days ago | `~` | Yellow `\033[1;33m` |
| Active | None of the above | ` ` | (no icon) |

The icon appears as a third column in the list display, between the dirty indicator and the branch name.

### Detection implementation

Three additional `git` subprocesses per worktree in the awk script (4 total, up from 1):

- `git -C <path> branch -vv` — parse `[gone]` in tracking info to detect remote-deleted branches
- `git -C <path> branch -r --merged HEAD` — check if branch is merged into the default branch
- Age derived from `git -C <path> log -1 --format=%ct` compared to current epoch

Default branch detection: `git symbolic-ref refs/remotes/origin/HEAD`, stripping to short name. Cached once at the start of `_hop_list()` and passed as an awk variable.

### Preview pane additions

A "Cleanup signals" section prepended to the existing preview output:

```
  Cleanup signals
  tracking: [gone] (remote branch deleted)
  merged:   yes (merged into main)
  last commit: 8 days ago
```

Only shown when at least one stale signal is present. Active worktrees show no cleanup section.

### `hop stale` subcommand

**With a TTY (interactive mode):**
- Launches fzf over stale worktrees (safe-to-remove + soft-stale) with `tab` for multi-select
- Header shows: `tab select  ·  enter remove selected  ·  esc cancel`
- On enter: shows summary of selected worktrees + prompt "Remove N worktrees? (y/N)"
- After confirmation: removes each, running per-worktree dirty check with individual "Remove anyway? (y/N)" for any with uncommitted changes

**Without a TTY / `--list` flag:**
- Prints stale worktree paths one per line (suitable for piping)

### Confirmation behavior (all removal paths)

| Path | Clean worktree | Dirty worktree |
|---|---|---|
| `ctrl-d` in fzf | "Remove `<branch>`? (y/N)" | Show uncommitted changes + "Remove anyway? (y/N)" |
| `hop stale` bulk | "Remove N worktrees? (y/N)" summary | Per-worktree "Remove anyway? (y/N)" for dirty ones |

Previously `ctrl-d` on clean worktrees removed silently — this is corrected.

---

## Feature 2: `hop new <branch>`

### Invocation

```
hop new <branch-name>
```

### Flow

1. Validate: must be inside a git repo, branch name must be provided
2. Detect default branch: `git symbolic-ref refs/remotes/origin/HEAD` → strip to short name. Fallback: try `main`, then `master`. Error if neither exists.
3. Fetch: `git fetch origin` (ensures new branch is off fresh upstream)
4. Compute path: sibling directory `$(git rev-parse --show-toplevel)/../<branch-name>`, preserving slashes as directory separators (e.g., `feat/my-feature` → `../feat/my-feature`, creating the `feat/` subdirectory if needed). Branch name is used as-is — no sanitization.
5. Create worktree + branch: `git worktree add -b <branch-name> <path> origin/<default-branch>`
6. Switch: `cd <path>`

Note: upstream tracking is intentionally left unset. The branch is created off `origin/<default>` as its starting point, but the user will push to `origin/<branch-name>` on their first push (`git push -u origin <branch-name>`). Setting upstream to the default branch here would cause `git push` to try pushing to the wrong remote branch.

### Error handling

- Path already exists → `hop: path <path> already exists`
- Branch already exists → `hop: branch <branch-name> already exists`
- Fetch failure → surface git's error message, abort
- No default branch detectable → `hop: could not detect default branch (set origin/HEAD or use --from)`

### Future work (not in scope)

- `--from <base>` flag to specify a base branch other than the default

---

## Feature 3: Relative path preservation on switch

### Behavior

When switching worktrees, compute the relative path from the current worktree root to `$PWD`. Append to the destination path. Land there if the directory exists, otherwise land at the worktree root.

**Example:**
- Current: `/projects/myapp-feat/src/components` (worktree root: `/projects/myapp-feat`)
- Destination: `/projects/myapp-main`
- Relative: `src/components`
- Land in: `/projects/myapp-main/src/components` if exists, else `/projects/myapp-main`

### Implementation

Two lines appended before the final `cd` in `hop()`:

```zsh
local rel="${PWD#$current_wt}"
[[ -n "$rel" && -d "$selected_path$rel" ]] && selected_path="$selected_path$rel"
```

Applies to `hop` (interactive switch). Does not apply to `hop new` (always lands at root of fresh worktree).

---

## Out of scope

- `--from <base>` flag for `hop new`
- Editor state restoration (Neovim session, VS Code workspace)
- GitHub PR integration (requires `gh`, optional dep)
- Config file support

---

## Verification plan

1. `hop list` — stale icons appear correctly for merged/gone branches, absent for active ones
2. `hop` interactive — stale icon visible in list, cleanup section in preview for stale worktrees
3. `ctrl-d` on clean worktree — confirmation prompt shown before removal
4. `ctrl-d` on dirty worktree — existing behavior preserved (show diff + confirm)
5. `hop stale` with TTY — fzf multi-select, summary confirmation, per-worktree dirty check
6. `hop stale` without TTY — prints paths only
7. `hop new feat/my-feature` — creates worktree at `../feat/my-feature` (slash preserved as directory), branch named `feat/my-feature`, switches in
8. `hop new` errors — missing name, existing branch, existing path, no network
9. Relative path preservation — switching from `src/components` lands in same path if exists
10. Relative path preservation — switching when subdir doesn't exist in target lands at root

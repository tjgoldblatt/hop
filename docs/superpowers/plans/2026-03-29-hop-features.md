# hop features Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add stale worktree detection/cleanup, `hop new <branch>` creation, and relative path preservation to hop.zsh.

**Architecture:** All changes are in the single file `hop.zsh`. The awk script (written to a tempfile by `_hop_write_awk`) gains stale detection logic with new git subprocesses and new awk variables passed in. Two new subcommands (`new`, `stale`) are dispatched from the top of `hop()`. The remove script is updated for consistent confirmation on clean worktrees.

**Tech Stack:** zsh, awk, git, fzf

---

## File map

| File | What changes |
|---|---|
| `hop.zsh` | All changes: awk script, `_hop_list()`, `hop()`, new `_hop_new()`, new `_hop_stale()`, updated remove script |

No new files are created. hop.zsh is a ~170-line single-file plugin sourced by zsh.

---

### Task 1: Add stale detection variables to the awk script

**Files:**
- Modify: `hop.zsh` — `_hop_write_awk()` function (lines 18–52)

This task adds four new git subprocesses inside the awk `{...}` block and computes a `stale` variable (`safe`, `soft`, or `active`) used in the next task for display. No display changes yet — just the detection logic.

- [ ] **Step 1: Read the current awk script block**

Open `hop.zsh` and locate `_hop_write_awk()`. The awk block starts at line 20 (`BEGIN { RS = ""; FS = "\n" }`) and the current dirty check is at line 35:
```awk
cmd = "git -C " q path q " status --porcelain 2>/dev/null | head -1"
cmd | getline out
close(cmd)
dirty = (out == "") ? "  " : "\033[1;33m●\033[0m "
```

- [ ] **Step 2: Add stale detection after the dirty check**

In `_hop_write_awk()`, after the `dirty` line and before the `marker` line, insert the following stale detection block. The variables `defbranch` and `now` are passed in from shell (added in Task 2):

```awk
    # stale detection
    cmd2 = "git -C " q path q " branch -vv 2>/dev/null"
    gone = 0
    while ((cmd2 | getline line2) > 0) {
        if (line2 ~ /^\*/ && line2 ~ /\[gone\]/) gone = 1
    }
    close(cmd2)

    cmd3 = "git -C " q path q " branch -r --merged HEAD 2>/dev/null"
    merged = 0
    while ((cmd3 | getline line3) > 0) {
        if (line3 ~ "origin/" defbranch) merged = 1
    }
    close(cmd3)

    cmd4 = "git -C " q path q " log -1 --format=%ct 2>/dev/null"
    lastcommit = 0
    cmd4 | getline lastcommit
    close(cmd4)
    age_days = (now - lastcommit + 0) / 86400

    if (gone && merged && out == "") {
        stale = "safe"
    } else if (gone || merged || age_days > 7) {
        stale = "soft"
    } else {
        stale = "active"
    }
```

The full updated `_hop_write_awk()` after this change (replace the entire function):

```zsh
_hop_write_awk() {
    cat > "$1" <<'HOPAWK'
BEGIN { RS = ""; FS = "\n" }
{
    path = ""; branch = ""; head = ""
    for (i = 1; i <= NF; i++) {
        if (substr($i, 1, 9) == "worktree ") path = substr($i, 10)
        else if (substr($i, 1, 7) == "branch ") {
            branch = substr($i, 8)
            sub("refs/heads/", "", branch)
        }
        else if (substr($i, 1, 5) == "HEAD ") head = substr($i, 6, 7)
    }
    if (path == "") next
    if (branch == "") branch = "(detached:" head ")"

    q = sprintf("%c", 34)
    cmd = "git -C " q path q " status --porcelain 2>/dev/null | head -1"
    cmd | getline out
    close(cmd)
    dirty = (out == "") ? "  " : "\033[1;33m●\033[0m "

    # stale detection
    cmd2 = "git -C " q path q " branch -vv 2>/dev/null"
    gone = 0
    while ((cmd2 | getline line2) > 0) {
        if (line2 ~ /^\*/ && line2 ~ /\[gone\]/) gone = 1
    }
    close(cmd2)

    cmd3 = "git -C " q path q " branch -r --merged HEAD 2>/dev/null"
    merged = 0
    while ((cmd3 | getline line3) > 0) {
        if (line3 ~ "origin/" defbranch) merged = 1
    }
    close(cmd3)

    cmd4 = "git -C " q path q " log -1 --format=%ct 2>/dev/null"
    lastcommit = 0
    cmd4 | getline lastcommit
    close(cmd4)
    age_days = (now - lastcommit + 0) / 86400

    if (gone && merged && out == "") {
        stale = "safe"
    } else if (gone || merged || age_days > 7) {
        stale = "soft"
    } else {
        stale = "active"
    }

    marker = (path == cur) ? "\033[1;35m> " : "  "
    if (pw > 10) {
        short = path; sub(home, "~", short)
        if (length(short) > pw) short = "..." substr(short, length(short) - pw + 4)
        fmt = "%s\033[2m%-" pw "s\033[0m %s\033[1;96m%s\033[0m\t%s\n"
    } else {
        short = ""
        fmt = "%s%s%s\033[1;96m%s\033[0m\t%s\n"
    }
    printf fmt, marker, short, dirty, branch, path
}
HOPAWK
}
```

- [ ] **Step 3: Verify the function is syntactically correct**

```bash
zsh -c 'source hop.zsh; echo ok'
```
Expected: `ok` (no errors)

- [ ] **Step 4: Commit**

```bash
git add hop.zsh
git commit -m "feat: add stale detection logic to awk script (no display yet)"
```

---

### Task 2: Display stale icon in list and pass new awk variables

**Files:**
- Modify: `hop.zsh` — `_hop_write_awk()` printf lines, `_hop_list()` function (lines 56–73)

This task wires up the `stale` variable computed in Task 1 to a visible icon column, and passes the required `defbranch` and `now` variables from the shell into awk.

- [ ] **Step 1: Update printf format strings in `_hop_write_awk()` to include stale icon**

In the awk script, replace the two `fmt`/`printf` lines (the `if (pw > 10)` block at the end of the `{...}` block):

```awk
    if (stale == "safe") {
        staleicon = "\033[1;31m✗\033[0m "
    } else if (stale == "soft") {
        staleicon = "\033[1;33m~\033[0m "
    } else {
        staleicon = "  "
    }

    marker = (path == cur) ? "\033[1;35m> " : "  "
    if (pw > 10) {
        short = path; sub(home, "~", short)
        if (length(short) > pw) short = "..." substr(short, length(short) - pw + 4)
        fmt = "%s\033[2m%-" pw "s\033[0m %s%s\033[1;96m%s\033[0m\t%s\n"
    } else {
        short = ""
        fmt = "%s%s%s%s\033[1;96m%s\033[0m\t%s\n"
    }
    printf fmt, marker, short, dirty, staleicon, branch, path
```

Note: `staleicon` is inserted between `dirty` and `branch` in both format strings. The wide format adds one `%s` between `\033[0m` and `\033[1;96m`; the narrow format adds one `%s` between the second and third `%s`.

The full updated awk block tail (replace from `marker =` to end of `}`) inside `_hop_write_awk()`:

```awk
    if (stale == "safe") {
        staleicon = "\033[1;31m✗\033[0m "
    } else if (stale == "soft") {
        staleicon = "\033[1;33m~\033[0m "
    } else {
        staleicon = "  "
    }

    marker = (path == cur) ? "\033[1;35m> " : "  "
    if (pw > 10) {
        short = path; sub(home, "~", short)
        if (length(short) > pw) short = "..." substr(short, length(short) - pw + 4)
        fmt = "%s\033[2m%-" pw "s\033[0m %s%s\033[1;96m%s\033[0m\t%s\n"
    } else {
        short = ""
        fmt = "%s%s%s%s\033[1;96m%s\033[0m\t%s\n"
    }
    printf fmt, marker, short, dirty, staleicon, branch, path
```

- [ ] **Step 2: Pass `defbranch` and `now` from `_hop_list()` into awk**

In `_hop_list()`, before the `git worktree list` pipe, detect the default branch and capture the current epoch. Then add `-v defbranch=` and `-v now=` to the `awk` invocation:

```zsh
_hop_list() {
    local cur="$1" awk_file="$2"
    local own_awk=0
    if [[ -z "$awk_file" ]]; then
        awk_file=$(mktemp "${TMPDIR:-/tmp}/hop-fmt.XXXXXX")
        own_awk=1
        _hop_write_awk "$awk_file"
    fi

    local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    local pw=$(( (cols / 2) - 43 ))
    (( pw < 0 )) && pw=0

    local defbranch
    defbranch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    [[ -z "$defbranch" ]] && { git show-ref --verify --quiet refs/heads/main 2>/dev/null && defbranch=main; }
    [[ -z "$defbranch" ]] && { git show-ref --verify --quiet refs/heads/master 2>/dev/null && defbranch=master; }
    [[ -z "$defbranch" ]] && defbranch=main  # last-resort fallback, merged check will just never match

    local now
    now=$(date +%s)

    git worktree list --porcelain \
    | awk -f "$awk_file" -v home="$HOME" -v cur="$cur" -v pw="$pw" \
          -v defbranch="$defbranch" -v now="$now"

    (( own_awk )) && rm -f "$awk_file"
}
```

- [ ] **Step 3: Also update the reload script in `hop()` to pass new variables**

In `hop()`, find the `cat > "$reload_script"` heredoc and add the two new awk variables. The updated reload script:

```zsh
    cat > "$reload_script" <<RELOAD
#!/bin/sh
defbranch=\$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
[ -z "\$defbranch" ] && defbranch=main
now=\$(date +%s)
pw=\$(( (\$(tput cols 2>/dev/null || echo 80) / 2) - 43 ))
git worktree list --porcelain | awk -f "$awk_file" -v home="$HOME" -v cur="$current_wt" -v pw="\$pw" -v defbranch="\$defbranch" -v now="\$now"
RELOAD
```

- [ ] **Step 4: Verify list renders without errors**

```bash
zsh -c 'source hop.zsh; hop list'
```
Expected: worktree list prints with no shell errors. Stale icons may not appear yet if all local worktrees are active (that's fine — the logic is correct).

- [ ] **Step 5: Commit**

```bash
git add hop.zsh
git commit -m "feat: display stale icon in worktree list"
```

---

### Task 3: Add cleanup signals section to fzf preview

**Files:**
- Modify: `hop.zsh` — `--preview` string inside `hop()` (around line 149)

The preview currently shows `git status` and `git log`. This task prepends a "Cleanup signals" section when the worktree has stale signals.

- [ ] **Step 1: Update the `--preview` block in `hop()`**

Find the `--preview='` string (currently around line 149). Replace it with the following. The shell inside fzf preview is `/bin/sh`, so use POSIX sh syntax only:

```zsh
              --preview='
                  p={-1}
                  gone=$(git -C "$p" branch -vv 2>/dev/null | awk "/^\*/ && /\[gone\]/ {print \"yes\"}")
                  merged_into=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s|refs/remotes/origin/||")
                  [ -z "$merged_into" ] && merged_into=main
                  merged=$(git -C "$p" branch -r --merged HEAD 2>/dev/null | grep -c "origin/$merged_into" || true)
                  lastct=$(git -C "$p" log -1 --format=%ct 2>/dev/null)
                  now=$(date +%s)
                  age=$(( (now - lastct) / 86400 ))
                  show_cleanup=0
                  [ -n "$gone" ] && show_cleanup=1
                  [ "$merged" -gt 0 ] 2>/dev/null && show_cleanup=1
                  [ "$age" -gt 7 ] 2>/dev/null && show_cleanup=1
                  if [ "$show_cleanup" = "1" ]; then
                      echo "\033[1;31m  Cleanup signals\033[0m"
                      [ -n "$gone" ] && echo "  tracking: [gone] (remote branch deleted)"
                      [ "$merged" -gt 0 ] 2>/dev/null && echo "  merged:   yes (merged into $merged_into)"
                      echo "  last commit: ${age} days ago"
                      echo ""
                  fi
                  echo "\033[1;96m  Status\033[0m"
                  git -c color.status=always -C "$p" status --short --branch 2>/dev/null || echo "  (no status)"
                  echo ""
                  echo "\033[1;96m  Recent commits\033[0m"
                  git -C "$p" log --oneline --graph --date=short --color=always \
                      --pretty="format:%C(auto)%cd %h%d %s" -8 2>/dev/null || echo "  (no log)"
              ' \
```

- [ ] **Step 2: Verify hop launches without syntax error**

```bash
zsh -c 'source hop.zsh; echo sourced ok'
```
Expected: `sourced ok`

- [ ] **Step 3: Commit**

```bash
git add hop.zsh
git commit -m "feat: add cleanup signals section to fzf preview pane"
```

---

### Task 4: Fix ctrl-d confirmation for clean worktrees + implement `hop stale`

**Files:**
- Modify: `hop.zsh` — remove script heredoc in `hop()`, new `_hop_stale()` function, dispatch in `hop()`

Currently `ctrl-d` on a clean worktree removes silently. This task adds a confirmation prompt for clean worktrees, then builds the `hop stale` subcommand on top of the same remove script.

- [ ] **Step 1: Update the remove script to always confirm**

In `hop()`, find the `cat > "$remove_script" <<'RMSCRIPT'` heredoc. Replace it with:

```zsh
    cat > "$remove_script" <<'RMSCRIPT'
#!/bin/sh
p="$1"
[ -z "$p" ] && exit 1
dirty=$(git -C "$p" status --porcelain 2>/dev/null)
branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
if [ -n "$dirty" ]; then
    echo ""
    printf "  \033[1;33m⚠  Worktree has uncommitted changes:\033[0m\n\n"
    git -C "$p" status --short 2>/dev/null | sed 's/^/    /'
    echo ""
    printf "  Remove \033[1;96m%s\033[0m anyway? (y/N) " "$branch"
    read ans
    case "$ans" in y|Y) git worktree remove --force -- "$p" 2>/dev/null ;; esac
else
    printf "  Remove \033[1;96m%s\033[0m? (y/N) " "$branch"
    read ans
    case "$ans" in y|Y) git worktree remove -- "$p" 2>/dev/null ;; esac
fi
RMSCRIPT
```

- [ ] **Step 2: Add the `_hop_stale()` function**

Add this function to `hop.zsh` between `_hop_list()` and `hop()` (i.e., after line 73 and before the `# ─── Main` banner):

```zsh
# ─── Stale cleanup ───────────────────────────────────────────────────────────

_hop_stale() {
    # Collect stale worktree paths by running the same detection logic used in
    # the awk script, but in shell so we can filter without fzf.
    local defbranch
    defbranch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    [[ -z "$defbranch" ]] && { git show-ref --verify --quiet refs/heads/main 2>/dev/null && defbranch=main; }
    [[ -z "$defbranch" ]] && { git show-ref --verify --quiet refs/heads/master 2>/dev/null && defbranch=master; }
    [[ -z "$defbranch" ]] && defbranch=main
    local now; now=$(date +%s)

    local -a stale_paths stale_branches
    local wt_root wt_branch
    while IFS= read -r line; do
        case "$line" in
            worktree\ *) wt_root="${line#worktree }" ;;
            branch\ *)
                wt_branch="${line#branch }"
                wt_branch="${wt_branch#refs/heads/}" ;;
        esac
        if [[ -z "$line" && -n "$wt_root" ]]; then
            # blank line = end of stanza, evaluate
            local gone merged age_days
            gone=$(git -C "$wt_root" branch -vv 2>/dev/null | awk '/^\*/ && /\[gone\]/ {print "yes"}')
            merged=$(git -C "$wt_root" branch -r --merged HEAD 2>/dev/null | grep -c "origin/$defbranch" 2>/dev/null || echo 0)
            local lastct; lastct=$(git -C "$wt_root" log -1 --format=%ct 2>/dev/null)
            age_days=$(( (now - lastct) / 86400 ))

            local is_stale=0
            [[ -n "$gone" ]] && is_stale=1
            (( merged > 0 )) && is_stale=1
            (( age_days > 7 )) && is_stale=1

            if (( is_stale )); then
                stale_paths+=("$wt_root")
                stale_branches+=("$wt_branch")
            fi
            wt_root=""; wt_branch=""
        fi
    done < <(git worktree list --porcelain; echo "")

    if [[ ${#stale_paths[@]} -eq 0 ]]; then
        echo "hop: no stale worktrees found"
        return 0
    fi

    # Non-interactive: no TTY or --list flag → print paths only
    if [[ ! -t 1 || "$1" == "--list" ]]; then
        printf '%s\n' "${stale_paths[@]}"
        return 0
    fi

    # Interactive: fzf multi-select
    if ! command -v fzf &>/dev/null; then
        echo "hop: fzf is required for interactive mode (https://github.com/junegunn/fzf)"
        printf '%s\n' "${stale_paths[@]}"
        return 1
    fi

    local selected
    selected=$(
        for i in "${!stale_paths[@]}"; do
            printf '%s\t%s\n' "${stale_branches[$i]}" "${stale_paths[$i]}"
        done \
        | fzf --ansi \
              --multi \
              --delimiter=$'\t' \
              --with-nth=1 \
              --no-sort \
              --color='pointer:magenta:bold,hl:magenta:bold,hl+:magenta:bold,fg+:bright-white:bold,bg+:#3a3a5c' \
              --header='  tab select  ·  enter remove selected  ·  esc cancel' \
              --header-first \
              --pointer='▸' \
              --prompt='  stale › ' \
        | cut -f2
    )

    [[ -z "$selected" ]] && return 0

    local -a to_remove
    while IFS= read -r p; do
        to_remove+=("$p")
    done <<< "$selected"

    local n=${#to_remove[@]}
    echo ""
    printf "  About to remove %d worktree(s):\n" "$n"
    for p in "${to_remove[@]}"; do
        printf "    %s\n" "$p"
    done
    echo ""
    printf "  Remove %d worktree(s)? (y/N) " "$n"
    read -r ans
    case "$ans" in
        y|Y) ;;
        *) echo "  Aborted."; return 0 ;;
    esac

    for p in "${to_remove[@]}"; do
        local dirty; dirty=$(git -C "$p" status --porcelain 2>/dev/null)
        local branch; branch=$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [[ -n "$dirty" ]]; then
            echo ""
            printf "  \033[1;33m⚠  %s has uncommitted changes:\033[0m\n\n" "$branch"
            git -C "$p" status --short 2>/dev/null | sed 's/^/    /'
            echo ""
            printf "  Remove anyway? (y/N) "
            read -r dirtrans
            case "$dirtrans" in
                y|Y) git worktree remove --force -- "$p" && echo "  Removed $p" ;;
                *) echo "  Skipped $p" ;;
            esac
        else
            git worktree remove -- "$p" && echo "  Removed $p"
        fi
    done
}
```

- [ ] **Step 3: Add `stale` dispatch to `hop()`**

In `hop()`, after the `list` subcommand block (around line 84), add the `stale` dispatch:

```zsh
    if [[ "$1" == "stale" ]]; then
        _hop_stale "${@:2}"
        return $?
    fi
```

- [ ] **Step 4: Verify sourcing and `hop stale` help path**

```bash
zsh -c 'source hop.zsh; echo sourced ok'
```
Expected: `sourced ok`

```bash
zsh -c 'source hop.zsh; hop stale --list 2>&1 || true'
```
Expected: Either prints worktree paths or `hop: no stale worktrees found` (depends on local repo state). No syntax error.

- [ ] **Step 5: Commit**

```bash
git add hop.zsh
git commit -m "feat: add hop stale subcommand + fix ctrl-d confirmation for clean worktrees"
```

---

### Task 5: Implement `hop new <branch>`

**Files:**
- Modify: `hop.zsh` — new `_hop_new()` function, dispatch in `hop()`

- [ ] **Step 1: Add `_hop_new()` function**

Add this function to `hop.zsh` after `_hop_stale()` and before the `# ─── Main` banner:

```zsh
# ─── New worktree ─────────────────────────────────────────────────────────────

_hop_new() {
    local branch="$1"
    if [[ -z "$branch" ]]; then
        echo "hop: usage: hop new <branch-name>"
        return 1
    fi

    # Detect default branch
    local defbranch
    defbranch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
    if [[ -z "$defbranch" ]]; then
        git show-ref --verify --quiet refs/remotes/origin/main 2>/dev/null && defbranch=main
    fi
    if [[ -z "$defbranch" ]]; then
        git show-ref --verify --quiet refs/remotes/origin/master 2>/dev/null && defbranch=master
    fi
    if [[ -z "$defbranch" ]]; then
        echo "hop: could not detect default branch (set origin/HEAD or use --from)"
        return 1
    fi

    # Check branch doesn't already exist
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        echo "hop: branch '$branch' already exists"
        return 1
    fi

    # Compute path: sibling dir preserving slash structure
    local repo_root; repo_root=$(git rev-parse --show-toplevel)
    local wt_path="${repo_root}/../${branch}"
    # Normalize: resolve .. but keep the branch-as-path structure
    wt_path=$(cd "$repo_root/.." && echo "$PWD/$branch")

    if [[ -e "$wt_path" ]]; then
        echo "hop: path '$wt_path' already exists"
        return 1
    fi

    # Fetch to ensure we're off fresh upstream
    echo "  Fetching origin..."
    if ! git fetch origin 2>&1; then
        echo "hop: fetch failed"
        return 1
    fi

    # Create parent directory if branch name contains slashes
    local wt_parent="${wt_path%/*}"
    if [[ "$wt_parent" != "$wt_path" ]]; then
        mkdir -p "$wt_parent" || { echo "hop: could not create directory '$wt_parent'"; return 1; }
    fi

    # Create worktree + branch
    echo "  Creating worktree at $wt_path..."
    if ! git worktree add -b "$branch" "$wt_path" "origin/$defbranch" 2>&1; then
        echo "hop: failed to create worktree"
        return 1
    fi

    echo "  Switching to $branch"
    cd "$wt_path"
}
```

- [ ] **Step 2: Add `new` dispatch to `hop()`**

In `hop()`, after the `stale` dispatch block, add:

```zsh
    if [[ "$1" == "new" ]]; then
        _hop_new "${@:2}"
        return $?
    fi
```

- [ ] **Step 3: Update the usage comment at the top of the file**

Find the comment block at lines 1–14 and update the Usage section:

```zsh
# Usage:
#   hop          - interactive worktree switcher (fzf)
#   hop list     - non-interactive list of worktrees
#   hop new      - create a new branch + worktree and switch into it
#   hop stale    - interactive cleanup of stale worktrees
```

And add to the Dependencies comment:

```zsh
# Dependencies: git, fzf, awk
```
(no change needed — fzf is already listed; `hop new` and `hop stale` only add dependency on git features that are already required)

- [ ] **Step 4: Verify sourcing**

```bash
zsh -c 'source hop.zsh; echo sourced ok'
```
Expected: `sourced ok`

- [ ] **Step 5: Commit**

```bash
git add hop.zsh
git commit -m "feat: add hop new <branch> subcommand"
```

---

### Task 6: Add relative path preservation on switch

**Files:**
- Modify: `hop.zsh` — final `cd` line in `hop()` (last line, currently `[[ -n "$selected_path" ]] && cd "$selected_path"`)

- [ ] **Step 1: Replace the final cd line in `hop()`**

Find the last line of `hop()`:
```zsh
    [[ -n "$selected_path" ]] && cd "$selected_path"
```

Replace with:
```zsh
    if [[ -n "$selected_path" ]]; then
        local rel="${PWD#$current_wt}"
        if [[ -n "$rel" && -d "$selected_path$rel" ]]; then
            cd "$selected_path$rel"
        else
            cd "$selected_path"
        fi
    fi
```

- [ ] **Step 2: Verify sourcing**

```bash
zsh -c 'source hop.zsh; echo sourced ok'
```
Expected: `sourced ok`

- [ ] **Step 3: Commit**

```bash
git add hop.zsh
git commit -m "feat: preserve relative path when switching worktrees"
```

---

### Task 7: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update Usage section**

Replace the existing Usage block:
```markdown
## Usage

```
hop          # interactive worktree switcher
hop list     # print worktrees (non-interactive)
```
```

With:
```markdown
## Usage

```
hop              # interactive worktree switcher
hop list         # print worktrees (non-interactive)
hop new <branch> # create a new branch + worktree and switch into it
hop stale        # interactive cleanup of stale worktrees
```
```

- [ ] **Step 2: Update Keybindings table**

The existing table covers `ctrl-d` but doesn't mention the new confirmation behavior. Add a note row:

```markdown
| `ctrl-d` | Remove selected worktree (always confirms) |
```

Replace the existing `ctrl-d` row (`Remove selected worktree`) with the above.

- [ ] **Step 3: Add Features section entries**

In the Features list, add:
```markdown
- **Stale indicators** — red ✗ or yellow ~ signals when a worktree's remote branch is gone or merged
- **Smart cleanup** — `hop stale` opens an interactive multi-select to bulk-remove stale worktrees
- **Smart creation** — `hop new feat/my-feature` creates a branch off origin/main, places the worktree at `../feat/my-feature`, and switches in
- **Path preservation** — switching worktrees lands you in the same subdirectory if it exists
```

- [ ] **Step 4: Commit**

```bash
git add README.md
git commit -m "docs: update README for new features"
```

---

## Verification checklist

After all tasks:

- [ ] `hop list` — stale icons appear for merged/gone branches, absent for active ones
- [ ] `hop` interactive — stale icon visible in list, cleanup section in preview for stale worktrees
- [ ] `ctrl-d` on clean worktree — "Remove `<branch>`? (y/N)" prompt shown
- [ ] `ctrl-d` on dirty worktree — show uncommitted changes + "Remove anyway? (y/N)"
- [ ] `hop stale` with TTY — fzf multi-select, summary confirmation, per-dirty-worktree prompts
- [ ] `hop stale --list` / piped — prints paths only
- [ ] `hop new feat/my-feature` — creates `../feat/my-feature`, branch `feat/my-feature`, switches in
- [ ] `hop new` without name — prints usage error
- [ ] `hop new` with existing branch — prints error, exits
- [ ] `hop new` with existing path — prints error, exits
- [ ] Relative path: switching from `src/components` lands there in destination if exists
- [ ] Relative path: switching when subdir absent in destination lands at root

# hop - fuzzy git worktree switcher
# https://github.com/tjgoldblatt/hop
#
# Usage:
#   hop          - interactive worktree switcher (fzf)
#   hop list     - non-interactive list of worktrees
#   hop new      - create a new branch + worktree and switch into it
#   hop stale    - interactive cleanup of stale worktrees
#
# Keybindings (in fzf):
#   enter        - switch to selected worktree
#   ctrl-d       - remove selected worktree (confirms if dirty)
#   ctrl-p       - toggle preview pane
#   esc / ctrl-c - cancel
#
# Dependencies: git, fzf, awk

# ─── Shared awk script ──────────────────────────────────────────────────────

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

    merged = 0
    if (branch != defbranch && defbranch != "") {
        cmd3 = "git -C " q path q " branch -r --merged HEAD 2>/dev/null"
        while ((cmd3 | getline line3) > 0) {
            if (line3 ~ ("origin/" defbranch)) merged = 1
        }
        close(cmd3)
    }

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
}
HOPAWK
}

# ─── Formatting ──────────────────────────────────────────────────────────────

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
    local cur_wt; cur_wt=$(git rev-parse --show-toplevel 2>/dev/null)

    local -a stale_paths stale_branches
    local wt_root wt_branch gone merged age_days lastct is_stale
    while IFS= read -r line; do
        case "$line" in
            worktree\ *) wt_root="${line#worktree }" ;;
            branch\ *)
                wt_branch="${line#branch }"
                wt_branch="${wt_branch#refs/heads/}" ;;
        esac
        if [[ -z "$line" && -n "$wt_root" ]]; then
            # blank line = end of stanza, evaluate
            gone=$(git -C "$wt_root" branch -vv 2>/dev/null | awk '/^\*/ && /\[gone\]/ {print "yes"}')
            if [[ "$wt_branch" != "$defbranch" && -n "$defbranch" ]]; then
                merged=$(git -C "$wt_root" branch -r --merged HEAD 2>/dev/null | grep -c "origin/$defbranch" 2>/dev/null || true)
            else
                merged=0
            fi
            lastct=$(git -C "$wt_root" log -1 --format=%ct 2>/dev/null)
            lastct=${lastct:-$now}
            age_days=$(( (now - lastct) / 86400 ))

            is_stale=0
            [[ -n "$gone" ]] && is_stale=1
            (( merged > 0 )) && is_stale=1
            (( age_days > 7 )) && is_stale=1

            if (( is_stale )) && [[ "$wt_root" != "$cur_wt" ]]; then
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
        local i
        for (( i = 1; i <= ${#stale_paths[@]}; i++ )); do
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
        echo "hop: could not detect default branch (run: git remote set-head origin --auto)"
        return 1
    fi

    # Check branch doesn't already exist
    if git show-ref --verify --quiet "refs/heads/$branch" 2>/dev/null; then
        echo "hop: branch '$branch' already exists"
        return 1
    fi

    # Compute path: sibling dir preserving slash structure
    local repo_root; repo_root=$(git rev-parse --show-toplevel)
    # Normalize: resolve .. but keep the branch-as-path structure
    local wt_path; wt_path=$(cd "$repo_root/.." && echo "$PWD/$branch")

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

    # Create parent directory if branch name contains slashes (e.g. feat/my-branch)
    if [[ "$branch" == */* ]]; then
        local wt_parent="${wt_path%/*}"
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

# ─── Main ────────────────────────────────────────────────────────────────────

hop() {
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "hop: not inside a git repository"
        return 1
    fi

    # non-interactive list
    if [[ "$1" == "list" ]]; then
        local cur
        cur=$(git rev-parse --show-toplevel 2>/dev/null)
        _hop_list "$cur"
        return 0
    fi

    if [[ "$1" == "stale" ]]; then
        _hop_stale "${@:2}"
        return $?
    fi

    if [[ "$1" == "new" ]]; then
        _hop_new "${@:2}"
        return $?
    fi

    if ! command -v fzf &>/dev/null; then
        echo "hop: fzf is required but not found (https://github.com/junegunn/fzf)"
        return 1
    fi

    local current_wt
    current_wt=$(git rev-parse --show-toplevel 2>/dev/null)

    # fzf bindings run in subshells and can't call shell functions,
    # so we write small scripts to temp files for reload/remove actions.
    local awk_file reload_script remove_script
    awk_file=$(mktemp "${TMPDIR:-/tmp}/hop-fmt.XXXXXX")
    reload_script=$(mktemp "${TMPDIR:-/tmp}/hop-reload.XXXXXX")
    remove_script=$(mktemp "${TMPDIR:-/tmp}/hop-remove.XXXXXX")
    trap 'rm -f "$awk_file" "$reload_script" "$remove_script"' EXIT INT TERM HUP

    _hop_write_awk "$awk_file"

    # reload script — re-renders the worktree list for fzf
    cat > "$reload_script" <<RELOAD
#!/bin/sh
defbranch=\$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
if [ -z "\$defbranch" ] && git show-ref --verify --quiet refs/heads/main 2>/dev/null; then defbranch=main; fi
if [ -z "\$defbranch" ] && git show-ref --verify --quiet refs/heads/master 2>/dev/null; then defbranch=master; fi
[ -z "\$defbranch" ] && defbranch=main
now=\$(date +%s)
pw=\$(( (\$(tput cols 2>/dev/null || echo 80) / 2) - 43 ))
git worktree list --porcelain | awk -f "$awk_file" -v home="$HOME" -v cur="$current_wt" -v pw="\$pw" -v defbranch="\$defbranch" -v now="\$now"
RELOAD

    # remove script — always confirms before removing
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

    chmod +x "$reload_script" "$remove_script"

    local selected_path
    selected_path=$(
        _hop_list "$current_wt" "$awk_file" \
        | fzf --ansi \
              --delimiter=$'\t' \
              --with-nth=1 \
              --no-sort \
              --color='pointer:magenta:bold,hl:magenta:bold,hl+:magenta:bold,fg+:bright-white:bold,bg+:#3a3a5c' \
              --header='  ctrl-d remove  ·  ctrl-p preview  ·  enter switch' \
              --header-first \
              --pointer='▸' \
              --prompt="  $(basename "$current_wt") › " \
              --preview='
                  p={-1}
                  gone=$(git -C "$p" branch -vv 2>/dev/null | awk "/^\*/ && /\[gone\]/ {print \"yes\"}")
                  merged_into=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed "s|refs/remotes/origin/||")
                  [ -z "$merged_into" ] && merged_into=main
                  merged=$(git -C "$p" branch -r --merged HEAD 2>/dev/null | grep -c "origin/$merged_into" || true)
                  lastct=$(git -C "$p" log -1 --format=%ct 2>/dev/null)
                  now=$(date +%s)
                  [ -z "$lastct" ] && lastct=$now
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
              --preview-window='right,50%,border-left,<100(hidden)' \
              --bind='esc:abort,ctrl-c:abort' \
              --bind='ctrl-p:toggle-preview' \
              --bind="ctrl-d:execute($remove_script {-1})+reload($reload_script)" \
        | cut -f2
    )

    trap - EXIT INT TERM HUP
    rm -f "$awk_file" "$reload_script" "$remove_script"

    if [[ -n "$selected_path" ]]; then
        local rel="${PWD#$current_wt}"
        if [[ -n "$rel" && "${rel:0:1}" == "/" && -d "$selected_path$rel" ]]; then
            cd "$selected_path$rel"
        else
            cd "$selected_path"
        fi
    fi
}

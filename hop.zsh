# hop - fuzzy git worktree switcher
# https://github.com/tjgoldblatt/hop
#
# Usage:
#   hop          - interactive worktree switcher (fzf)
#   hop list     - non-interactive list of worktrees
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

    git worktree list --porcelain \
    | awk -f "$awk_file" -v home="$HOME" -v cur="$cur" -v pw="$pw"

    (( own_awk )) && rm -f "$awk_file"
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
pw=\$(( (\$(tput cols 2>/dev/null || echo 80) / 2) - 43 ))
git worktree list --porcelain | awk -f "$awk_file" -v home="$HOME" -v cur="$current_wt" -v pw="\$pw"
RELOAD

    # remove script — confirms removal if worktree has uncommitted changes
    cat > "$remove_script" <<'RMSCRIPT'
#!/bin/sh
p="$1"
[ -z "$p" ] && exit 1
dirty=$(git -C "$p" status --porcelain 2>/dev/null)
if [ -n "$dirty" ]; then
    echo ""
    printf "  \033[1;33m⚠  Worktree has uncommitted changes:\033[0m\n\n"
    git -C "$p" status --short 2>/dev/null | sed 's/^/    /'
    echo ""
    printf "  Remove anyway? (y/N) "
    read ans
    case "$ans" in y|Y) git worktree remove --force -- "$p" 2>/dev/null ;; esac
else
    git worktree remove -- "$p" 2>/dev/null
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

    [[ -n "$selected_path" ]] && cd "$selected_path"
}

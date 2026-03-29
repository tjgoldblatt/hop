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

# ─── Formatting ──────────────────────────────────────────────────────────────

_hop_list() {
    local cur="$1"
    local cols=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
    local pane=$(( cols / 2 ))
    # path budget = pane - marker(2) - dirty(2) - branch(~35) - padding(4)
    local pw=$(( pane - 43 ))
    (( pw < 0 )) && pw=0

    git worktree list --porcelain \
    | awk -v home="$HOME" -v cur="$cur" -v pw="$pw" '
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
        cmd = "git -C " q path q " status --porcelain 2>/dev/null"
        cmd | getline out
        close(cmd)
        dirty = (out == "") ? "  " : "\033[1;33m●\033[0m "

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
    }'
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
    local reload_script remove_script
    reload_script=$(mktemp "${TMPDIR:-/tmp}/hop-reload.XXXXXX")
    remove_script=$(mktemp "${TMPDIR:-/tmp}/hop-remove.XXXXXX")
    trap 'rm -f "$reload_script" "$remove_script"' EXIT INT TERM HUP

    # reload script — re-renders the worktree list for fzf
    cat > "$reload_script" <<RELOAD
#!/bin/sh
git worktree list --porcelain | awk -v home="$HOME" -v cur="$current_wt" -v pw=$(( (${COLUMNS:-$(tput cols 2>/dev/null || echo 80)} / 2) - 43 )) '
BEGIN { RS = ""; FS = "\\n" }
{
    path = ""; branch = ""; head = ""
    for (i = 1; i <= NF; i++) {
        if (substr(\$i, 1, 9) == "worktree ") path = substr(\$i, 10)
        else if (substr(\$i, 1, 7) == "branch ") {
            branch = substr(\$i, 8)
            sub("refs/heads/", "", branch)
        }
        else if (substr(\$i, 1, 5) == "HEAD ") head = substr(\$i, 6, 7)
    }
    if (path == "") next
    if (branch == "") branch = "(detached:" head ")"
    q = sprintf("%c", 34)
    cmd = "git -C " q path q " status --porcelain 2>/dev/null"
    cmd | getline out
    close(cmd)
    dirty = (out == "") ? "  " : "\\033[1;33m\xe2\x97\x8f\\033[0m "
    marker = (path == cur) ? "\\033[1;35m> " : "  "
    if (pw > 10) {
        short = path; sub(home, "~", short)
        if (length(short) > pw) short = "..." substr(short, length(short) - pw + 4)
        fmt = "%s\\033[2m%-" pw "s\\033[0m %s\\033[1;96m%s\\033[0m\\t%s\\n"
    } else {
        short = ""
        fmt = "%s%s%s\\033[1;96m%s\\033[0m\\t%s\\n"
    }
    printf fmt, marker, short, dirty, branch, path
}'
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
    case "$ans" in y|Y) git worktree remove --force "$p" 2>/dev/null ;; esac
else
    git worktree remove "$p" 2>/dev/null
fi
RMSCRIPT

    chmod +x "$reload_script" "$remove_script"

    local selected_path
    selected_path=$(
        _hop_list "$current_wt" \
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

    rm -f "$reload_script" "$remove_script"
    trap - EXIT INT TERM HUP

    [[ -n "$selected_path" ]] && cd "$selected_path"
}

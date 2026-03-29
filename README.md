# hop

Fuzzy git worktree switcher powered by [fzf](https://github.com/junegunn/fzf).

![hop demo](screenshots/demo.gif)

Hop between worktrees with a single keystroke. See branch names, dirty state, and a live preview of status and recent commits — all without leaving the terminal.

## Features

- **Fuzzy switching** — type to filter, enter to switch
- **Dirty indicators** — yellow dot shows worktrees with uncommitted changes
- **Live preview** — branch status and recent commits in the preview pane
- **Inline removal** — ctrl-d removes a worktree (confirms if dirty)
- **Responsive layout** — adapts columns to terminal width
- **Stale indicators** — red ✗ or yellow ~ signals when a worktree's remote branch is gone or merged
- **Smart cleanup** — `hop stale` opens an interactive multi-select to bulk-remove stale worktrees
- **Smart creation** — `hop new feat/my-feature` creates a branch off origin/main, places the worktree at `../feat/my-feature`, and switches in
- **Path preservation** — switching worktrees lands you in the same subdirectory if it exists

## Install

### Homebrew

```zsh
brew tap tjgoldblatt/hop
brew install hop
```

After install, Homebrew will print the exact line to add to your `~/.zshrc` or `~/.bashrc`.

### Plugin manager

**zinit:**
```zsh
zinit light tjgoldblatt/hop
```

**sheldon:**
```toml
[plugins.hop]
github = "tjgoldblatt/hop"
```

**antidote:**
```zsh
tjgoldblatt/hop
```

**oh-my-zsh:**
```zsh
git clone https://github.com/tjgoldblatt/hop ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/hop
# then add 'hop' to plugins=(...) in .zshrc
```

### Manual

```zsh
git clone https://github.com/tjgoldblatt/hop ~/.hop
echo 'source ~/.hop/hop.zsh' >> ~/.zshrc
```

## Usage

```
hop              # interactive worktree switcher
hop list         # print worktrees (non-interactive)
hop new <branch> # create a new branch + worktree and switch into it
hop stale        # interactive cleanup of stale worktrees
```

### Keybindings

| Key | Action |
|-----|--------|
| `enter` | Switch to selected worktree |
| `ctrl-d` | Remove selected worktree (always confirms) |
| `ctrl-p` | Toggle preview pane |
| `esc` / `ctrl-c` | Cancel |

## Dependencies

- [git](https://git-scm.com/)
- [fzf](https://github.com/junegunn/fzf)
- awk (ships with macOS and most Linux distros)

## License

MIT

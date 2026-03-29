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

## Install

### Plugin manager (recommended)

**zinit:**
```zsh
zinit light tj/hop
```

**sheldon:**
```toml
[plugins.hop]
github = "tj/hop"
```

**antidote:**
```zsh
tj/hop
```

**oh-my-zsh:**
```zsh
git clone https://github.com/tj/hop ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/hop
# then add 'hop' to plugins=(...) in .zshrc
```

### Manual

```zsh
git clone https://github.com/tj/hop ~/.hop
echo 'source ~/.hop/hop.zsh' >> ~/.zshrc
```

## Usage

```
hop          # interactive worktree switcher
hop list     # print worktrees (non-interactive)
```

### Keybindings

| Key | Action |
|-----|--------|
| `enter` | Switch to selected worktree |
| `ctrl-d` | Remove selected worktree |
| `ctrl-p` | Toggle preview pane |
| `esc` / `ctrl-c` | Cancel |

## Dependencies

- [git](https://git-scm.com/)
- [fzf](https://github.com/junegunn/fzf)
- awk (ships with macOS and most Linux distros)

## License

MIT

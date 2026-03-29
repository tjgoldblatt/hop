# hop Homebrew Distribution — Design Spec

**Date:** 2026-03-29
**Status:** Approved

---

## Overview

Distribute hop via a Homebrew tap so users can install and update with `brew install` and `brew upgrade`. Targets both zsh and bash users. No changes to `hop.zsh` or the plugin manager install path.

---

## Repository Structure

Two GitHub repos:

- **`tjgoldblatt/hop`** — existing repo, unchanged. `hop.zsh` stays canonical.
- **`tjgoldblatt/homebrew-hop`** — new repo. Contains one file: `Formula/hop.rb`.

The tap follows Homebrew's naming convention: a repo named `homebrew-<name>` under the same GitHub account is tappable as `brew tap tjgoldblatt/hop`.

---

## Formula Design

File: `homebrew-hop/Formula/hop.rb`

```ruby
class Hop < Formula
  desc "Fuzzy git worktree switcher powered by fzf"
  homepage "https://github.com/tjgoldblatt/hop"
  url "https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "<computed at release time>"
  license "MIT"

  depends_on "fzf"

  def install
    share.install "hop.zsh"
    (share/"hop.sh").make_symlink share/"hop.zsh"
  end

  def caveats
    <<~EOS
      To use hop, add this to your shell config (~/.zshrc or ~/.bashrc):
        source #{opt_share}/hop.zsh

      Then restart your shell or run:
        source #{opt_share}/hop.zsh
    EOS
  end

  test do
    system "bash", "-c", "source #{share}/hop.zsh && type hop"
  end
end
```

**Key decisions:**
- `hop.zsh` is installed to `$(brew --prefix)/share/hop/hop.zsh`
- `hop.sh` is a symlink to `hop.zsh` in the same directory (for bash users who prefer the `.sh` extension)
- `fzf` declared as a dependency so it is pulled in automatically
- `test` block validates bash compatibility at `brew test` time
- `caveats` block prints the source line immediately after install

---

## Release Workflow

Homebrew formulas pin to a specific tagged release + SHA256. The release process:

1. Tag the release in `hop`: `git tag v1.x.x && git push origin v1.x.x`
2. GitHub generates tarball at: `https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.x.x.tar.gz`
3. Compute SHA256: `curl -sL <tarball-url> | shasum -a 256`
4. Update `Formula/hop.rb` — bump `url` and `sha256`
5. Commit and push to `homebrew-hop`

Users receive the update via `brew upgrade hop` with no other action required.

Document this process in `RELEASING.md` in the `hop` repo.

---

## User Install Experience

```zsh
brew tap tjgoldblatt/hop
brew install hop
# Homebrew prints caveats with the exact source line:
# source /usr/local/share/hop/hop.zsh  (or /opt/homebrew/share/hop/hop.zsh on Apple Silicon)
```

One-time setup: user adds the source line to their `.zshrc` or `.bashrc`. All future updates: `brew upgrade hop`.

---

## README Update

Add a **Homebrew** section as the first install option (before plugin managers):

```md
### Homebrew (recommended for non-plugin-manager users)

\`\`\`zsh
brew tap tjgoldblatt/hop
brew install hop
\`\`\`

After install, Homebrew will print the line to add to your `~/.zshrc` or `~/.bashrc`.
```

The existing plugin manager section remains unchanged below it.

---

## Bash Compatibility

`hop.zsh` is already bash-compatible — no zsh-specific syntax is used. The `hop.sh` symlink allows bash users to source it with a shell-agnostic filename. No code changes to `hop.zsh` are required.

---

## Out of Scope

- Homebrew Core submission (`homebrew/homebrew-core`) — defer until hop has sufficient GitHub stars/usage
- Automatic formula updates (e.g. via GitHub Actions) — manual update process is sufficient for now
- Fish shell support — requires a separate rewrite due to incompatible syntax

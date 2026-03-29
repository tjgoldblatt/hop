---
name: Homebrew distribution setup
description: How hop is distributed via Homebrew tap, release process, and relevant files
type: project
---

hop is distributed via a Homebrew tap at `tjgoldblatt/homebrew-hop`.

**Why:** Makes hop installable with `brew install` and upgradeable with `brew upgrade` for users who don't use zsh plugin managers.

**How to apply:** When releasing a new version of hop, follow the release process in `RELEASING.md` in the hop repo root.

## Release process (summary)
1. Tag the release: `git tag vX.Y.Z && git push origin vX.Y.Z`
2. Compute SHA256: `curl -sL https://github.com/tjgoldblatt/hop/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256`
3. Update `Formula/hop.rb` in the `homebrew-hop` repo — bump `url` and `sha256`
4. Commit and push to homebrew-hop

Full details: `RELEASING.md` in the hop repo root.

## Key files
- `homebrew-hop/Formula/hop.rb` — the Homebrew formula (in separate repo)
- `RELEASING.md` — step-by-step release checklist (in hop repo)

## Architecture
- `hop.zsh` stays canonical (unchanged for plugin manager users)
- Formula installs `hop.zsh` to `$(brew --prefix)/share/hop/hop.zsh`
- `hop.sh` is a symlink to `hop.zsh` for bash users
- `fzf` is declared as a Homebrew dependency (auto-installed)
- Caveats block prints the exact `source` line after `brew install`

## User install
```zsh
brew tap tjgoldblatt/hop
brew install hop
# source line printed in caveats — add to ~/.zshrc or ~/.bashrc
```

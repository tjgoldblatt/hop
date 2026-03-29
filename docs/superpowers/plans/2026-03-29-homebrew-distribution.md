# hop Homebrew Distribution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish hop to a Homebrew tap so users can install and update via `brew install` and `brew upgrade`.

**Architecture:** Create a new `tjgoldblatt/homebrew-hop` GitHub repo containing a single Homebrew formula. Tag a `v1.0.0` release on the existing `hop` repo, compute its SHA256, wire up the formula, and update the README install section.

**Tech Stack:** Ruby (Homebrew formula DSL), GitHub (repo + releases), zsh/bash

---

## Files

| Action | File | Purpose |
|--------|------|---------|
| Create (new repo) | `Formula/hop.rb` | Homebrew formula for hop |
| Create (new repo) | `README.md` | Minimal tap README |
| Create (hop repo) | `RELEASING.md` | Step-by-step release process |
| Modify (hop repo) | `README.md` | Add Homebrew install section |

---

### Task 1: Tag v1.0.0 release on the hop repo

**Files:**
- No file changes — git operations only

- [ ] **Step 1: Verify the current state of main is releasable**

```bash
cd /Users/tj/Desktop/SoftwareDevelopment/SideProjects/hop
git log --oneline -5
git status
```

Expected: clean working tree, recent commits look good.

- [ ] **Step 2: Create and push the v1.0.0 tag**

```bash
git tag v1.0.0
git push origin v1.0.0
```

Expected: tag pushed, GitHub creates a tarball automatically at:
`https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.0.0.tar.gz`

- [ ] **Step 3: Compute the SHA256 of the release tarball**

```bash
curl -sL https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.0.0.tar.gz | shasum -a 256
```

Expected output example: `a3f1c2...  -`

**Save the 64-character hex string** — you'll need it in Task 2.

---

### Task 2: Create the homebrew-hop GitHub repository

**Files:**
- Create (new repo): `Formula/hop.rb`
- Create (new repo): `README.md`

- [ ] **Step 1: Create the repo on GitHub**

```bash
gh repo create tjgoldblatt/homebrew-hop --public --description "Homebrew tap for hop — fuzzy git worktree switcher"
```

Expected: repo URL printed, e.g. `https://github.com/tjgoldblatt/homebrew-hop`

- [ ] **Step 2: Clone it locally**

```bash
cd ~/Desktop/SoftwareDevelopment/SideProjects
git clone https://github.com/tjgoldblatt/homebrew-hop
cd homebrew-hop
```

- [ ] **Step 3: Create the Formula directory**

```bash
mkdir Formula
```

- [ ] **Step 4: Write the formula file**

Create `Formula/hop.rb` with the SHA256 from Task 1 Step 3:

```ruby
class Hop < Formula
  desc "Fuzzy git worktree switcher powered by fzf"
  homepage "https://github.com/tjgoldblatt/hop"
  url "https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "<SHA256-FROM-TASK-1-STEP-3>"
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

- [ ] **Step 5: Write the tap README**

Create `README.md`:

```markdown
# homebrew-hop

Homebrew tap for [hop](https://github.com/tjgoldblatt/hop) — fuzzy git worktree switcher powered by fzf.

## Install

\`\`\`zsh
brew tap tjgoldblatt/hop
brew install hop
\`\`\`

After install, Homebrew will print the line to add to your `~/.zshrc` or `~/.bashrc`.
```

- [ ] **Step 6: Commit and push**

```bash
git add Formula/hop.rb README.md
git commit -m "feat: add hop formula v1.0.0"
git push origin main
```

Expected: both files pushed to GitHub.

---

### Task 3: Verify the tap works end-to-end

**Files:** No changes — verification only

- [ ] **Step 1: Tap the repo**

```bash
brew tap tjgoldblatt/hop
```

Expected: `==> Tapping tjgoldblatt/hop` with no errors.

- [ ] **Step 2: Install hop via the tap**

```bash
brew install hop
```

Expected:
- `fzf` installed if not already present
- `hop.zsh` installed to `$(brew --prefix)/share/hop/hop.zsh`
- Caveats section prints the source line

- [ ] **Step 3: Run the formula test**

```bash
brew test hop
```

Expected: `Testing hop` → passes (bash can source hop.zsh and `type hop` succeeds)

- [ ] **Step 4: Verify the symlink exists**

```bash
ls -la $(brew --prefix)/share/hop/
```

Expected output:
```
hop.sh -> /opt/homebrew/share/hop/hop.zsh   (symlink)
hop.zsh                                      (regular file)
```

- [ ] **Step 5: Verify sourcing works in bash**

```bash
bash -c "source $(brew --prefix)/share/hop/hop.zsh && type hop"
```

Expected: `hop is a function`

---

### Task 4: Add RELEASING.md to the hop repo

**Files:**
- Create: `RELEASING.md` in `tjgoldblatt/hop`

- [ ] **Step 1: Write RELEASING.md**

```bash
cd /Users/tj/Desktop/SoftwareDevelopment/SideProjects/hop
```

Create `RELEASING.md`:

```markdown
# Releasing hop

## Steps

1. **Tag the release** in this repo:

   \`\`\`bash
   git tag v1.x.x
   git push origin v1.x.x
   \`\`\`

2. **Compute the SHA256** of the release tarball:

   \`\`\`bash
   curl -sL https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.x.x.tar.gz | shasum -a 256
   \`\`\`

3. **Update the formula** in [homebrew-hop](https://github.com/tjgoldblatt/homebrew-hop):

   Edit `Formula/hop.rb` — bump `url` (new tag) and `sha256` (output from step 2).

4. **Commit and push** to homebrew-hop:

   \`\`\`bash
   git add Formula/hop.rb
   git commit -m "chore: bump hop to v1.x.x"
   git push origin main
   \`\`\`

Users will receive the update automatically via `brew upgrade hop`.
```

- [ ] **Step 2: Commit**

```bash
git add RELEASING.md
git commit -m "docs: add release process for Homebrew tap"
git push origin main
```

---

### Task 5: Update the hop README with Homebrew install section

**Files:**
- Modify: `README.md` in `tjgoldblatt/hop`

- [ ] **Step 1: Open README.md**

The current Install section starts with `### Plugin manager (recommended)`. Replace the entire `## Install` section with:

```markdown
## Install

### Homebrew

\`\`\`zsh
brew tap tjgoldblatt/hop
brew install hop
\`\`\`

After install, Homebrew will print the exact line to add to your `~/.zshrc` or `~/.bashrc`.

### Plugin manager

**zinit:**
\`\`\`zsh
zinit light tjgoldblatt/hop
\`\`\`

**sheldon:**
\`\`\`toml
[plugins.hop]
github = "tjgoldblatt/hop"
\`\`\`

**antidote:**
\`\`\`zsh
tjgoldblatt/hop
\`\`\`

**oh-my-zsh:**
\`\`\`zsh
git clone https://github.com/tjgoldblatt/hop ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/hop
# then add 'hop' to plugins=(...) in .zshrc
\`\`\`

### Manual

\`\`\`zsh
git clone https://github.com/tjgoldblatt/hop ~/.hop
echo 'source ~/.hop/hop.zsh' >> ~/.zshrc
\`\`\`
```

- [ ] **Step 2: Commit and push**

```bash
git add README.md
git commit -m "docs: add Homebrew install option to README"
git push origin main
```

---

## Self-Review Checklist

- [x] **Tag v1.0.0** — Task 1
- [x] **Formula with correct url/sha256/install/caveats/test** — Task 2
- [x] **homebrew-hop repo created and pushed** — Task 2
- [x] **End-to-end verification (tap, install, test, symlink, bash)** — Task 3
- [x] **RELEASING.md** — Task 4
- [x] **README updated** — Task 5
- [x] No placeholders — SHA256 step is explicit; formula code is complete
- [x] No out-of-scope work (no GitHub Actions, no homebrew-core)

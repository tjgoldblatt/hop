# Releasing hop

## Steps

1. **Tag the release** in this repo:

   ```bash
   git tag v1.x.x
   git push origin v1.x.x
   ```

   > **Important:** Tag the commit that represents the actual release state — not a later docs or meta commit. Check `git log --oneline` and tag the last substantive code commit.

2. **Compute the SHA256** of the release tarball:

   ```bash
   curl -sL https://github.com/tjgoldblatt/hop/archive/refs/tags/v1.x.x.tar.gz | shasum -a 256
   ```

   > **Note:** GitHub's CDN may take a moment to serve the correct tarball after pushing a new tag. If the SHA256 seems wrong, wait 30 seconds and try again.

3. **Update the formula** in [homebrew-hop](https://github.com/tjgoldblatt/homebrew-hop):

   Edit `Formula/hop.rb` — bump `url` (new tag) and `sha256` (output from step 2).

4. **Commit and push** to homebrew-hop:

   ```bash
   git add Formula/hop.rb
   git commit -m "chore: bump hop to v1.x.x"
   git push origin main
   ```

5. **Verify** the new version installs:

   ```bash
   brew update
   brew upgrade hop
   brew test hop
   ```

Users will receive the update automatically via `brew upgrade hop`.

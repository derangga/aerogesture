# Release Guide

Step-by-step guide to release AeroGesture via GitHub Releases and Homebrew tap.

The CI workflow (`.github/workflows/release.yml`) automates most of the process: building binaries for both architectures (arm64 + x86_64), creating the GitHub Release, generating the Homebrew formula, and pushing it to [derangga/homebrew-formulae](https://github.com/derangga/homebrew-formulae).

---

## Prerequisites

These are one-time setup steps before your first release.

### 1. Verify `gh` CLI is authenticated

```bash
gh auth status
```

### 2. Create the `TAP_GITHUB_TOKEN` secret

The CI workflow needs a GitHub Personal Access Token (PAT) to push the formula to `derangga/homebrew-formulae`. This token is referenced as `secrets.TAP_GITHUB_TOKEN` in the workflow.

**Generate the token:**

1. Go to https://github.com/settings/tokens?type=beta (Fine-grained tokens)
2. Click **"Generate new token"**
3. Configure:
   - **Token name**: `homebrew-tap-push`
   - **Expiration**: 90 days (or your preference -- you'll need to rotate it before expiry)
   - **Repository access**: Select **"Only select repositories"** and pick `derangga/homebrew-formulae`
   - **Permissions**: Under **Repository permissions**, set:
     - **Contents**: Read and write (to push the formula file)
4. Click **"Generate token"** and copy it immediately

**Add it as a repository secret:**

```bash
gh secret set TAP_GITHUB_TOKEN --repo derangga/aerogesture
```

Paste the token when prompted. This stores it encrypted in the `aerogesture` repo, accessible only by GitHub Actions.

> **Note**: If the token expires, the `update-homebrew` job will fail with a 403 error. Regenerate and re-set the secret with the same command above.

### 3. Verify the tap repo structure

Your tap repo should already have `phunter.rb` at the root. The CI will add `aerogesture.rb` at the same level. No `Formula/` subdirectory needed.

```bash
gh api repos/derangga/homebrew-formulae/contents/ --jq '.[].name'
```

Expected output should include `phunter.rb` (and `aerogesture.rb` after first release).

---

## Releasing a New Version

### Step 1: Make sure the project builds cleanly

```bash
swift build -c release
```

Fix any errors before proceeding. This is the only quality gate -- there is no test suite yet.

### Step 2: Commit and push all changes

```bash
git add <files>
git commit -m "Your commit message"
git pull --rebase
git push
```

Make sure your working tree is clean and up to date with remote.

### Step 3: Decide on a version number

Follow [Semantic Versioning](https://semver.org/):

| Change type | Bump | Example |
|---|---|---|
| First release | - | `v0.1.0` |
| Bug fix | patch | `v0.1.0` -> `v0.1.1` |
| New feature (backward-compatible) | minor | `v0.1.0` -> `v0.2.0` |
| Breaking change | major | `v0.1.0` -> `v1.0.0` |

Check existing tags:

```bash
git tag -l
```

### Step 4: Create and push the tag

```bash
git tag -a v0.1.0 -m "Initial release"
git push origin v0.1.0
```

This triggers the CI workflow automatically.

### Step 5: Monitor the CI pipeline

Watch the workflow run in your terminal:

```bash
gh run watch
```

Or list recent runs to find it:

```bash
gh run list --workflow=release.yml --limit=3
```

The workflow has 3 jobs that run sequentially:

1. **`build`** (macos-14) -- Builds release binaries for arm64 and x86_64, creates `.tar.gz` archives with SHA256 checksums
2. **`release`** (ubuntu-latest) -- Downloads artifacts from the build step, creates a GitHub Release with auto-generated release notes, and attaches the archives
3. **`update-homebrew`** (ubuntu-latest) -- Downloads the release archives, computes SHA256 hashes, generates `aerogesture.rb` formula, and pushes it to `derangga/homebrew-formulae`

### Step 6: Verify the release

Once the workflow completes successfully:

**Check the GitHub Release:**

```bash
gh release view v0.1.0
```

Or open it in the browser:

```bash
gh release view v0.1.0 --web
```

You should see two attached archives:
- `aerogesture_0.1.0_macos_arm64.tar.gz`
- `aerogesture_0.1.0_macos_x86_64.tar.gz`

**Check the formula was pushed to the tap:**

```bash
gh api repos/derangga/homebrew-formulae/contents/aerogesture.rb --jq '.sha' && echo "Formula exists"
```

### Step 7: Test the Homebrew installation

```bash
brew tap derangga/formulae
brew install aerogesture
```

If you already have it installed from a previous release:

```bash
brew update
brew upgrade aerogesture
```

Verify it works:

```bash
aerogesture --help
```

Start as a background service (optional):

```bash
brew services start aerogesture
```

---

## Quick Reference (Future Releases)

```bash
# 1. Make sure everything builds and is pushed
swift build -c release
git push

# 2. Tag and push -- this triggers the entire CI pipeline
git tag -a v0.2.0 -m "Description of this release"
git push origin v0.2.0

# 3. Watch it run
gh run watch

# 4. Verify
gh release view v0.2.0

# 5. Users upgrade with
brew update && brew upgrade aerogesture
```

---

## Troubleshooting

### CI `build` job fails

- Check Swift build errors: `gh run view <run-id> --log-failed`
- Verify the tagged commit builds locally: `git checkout v0.1.0 && swift build -c release`

### CI `update-homebrew` job fails with 403

- The `TAP_GITHUB_TOKEN` secret has likely expired
- Regenerate the PAT and update the secret:
  ```bash
  gh secret set TAP_GITHUB_TOKEN --repo derangga/aerogesture
  ```
- Re-run only the failed job:
  ```bash
  gh run rerun <run-id> --job <job-id>
  ```

### `brew install` fails

- Make sure Xcode CLT are installed: `xcode-select --install`
- Try untapping and re-tapping:
  ```bash
  brew untap derangga/formulae
  brew tap derangga/formulae
  brew install aerogesture
  ```

### SHA256 mismatch during `brew install`

- GitHub release assets may take a moment to propagate. Wait a minute, then:
  ```bash
  brew fetch --force aerogesture
  brew install aerogesture
  ```

### Users get "permission denied" at runtime

- AeroGesture needs Accessibility access: **System Settings > Privacy & Security > Accessibility**
- The binary path changes between direct install and Homebrew install; users may need to re-grant access after upgrading

### Deleting a broken release to redo it

If a release went wrong and you need to redo it:

```bash
# Delete the GitHub release and the tag
gh release delete v0.1.0 --yes
git push --delete origin v0.1.0
git tag -d v0.1.0

# Fix the issue, then re-tag and push
git tag -a v0.1.0 -m "Initial release"
git push origin v0.1.0
```

#!/bin/zsh

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  script/release-homebrew.sh <version> [--publish]

Examples:
  script/release-homebrew.sh 1.0.10
  script/release-homebrew.sh 1.0.10 --publish

What it does:
  1. Bumps Info.plist CFBundleShortVersionString and CFBundleVersion.
  2. Builds RELEASE=1 ./build-app.sh.
  3. Creates dist/Notch-<version>.zip.
  4. Updates /opt/homebrew/Library/Taps/promex04/homebrew-tap/Casks/notch.rb.
  5. Commits app version + tap cask changes.

With --publish, it also:
  6. Creates/uploads GitHub release asset in ProMeX04/notch-releases.
  7. Pushes notch-app and homebrew-tap commits.

Safety:
  - Refuses to publish if GitHub release tag already exists.
  - Refuses to publish if Homebrew cask already has the requested version.
  - Does not commit .claude/settings.json.
EOF
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
    usage
    exit 2
fi

VERSION="$1"
PUBLISH="0"
if [[ $# -eq 2 ]]; then
    if [[ "$2" != "--publish" ]]; then
        usage
        exit 2
    fi
    PUBLISH="1"
fi

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
    echo "Version must look like 1.2.3" >&2
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAP_DIR="/opt/homebrew/Library/Taps/promex04/homebrew-tap/Casks"
CASK_FILE="$TAP_DIR/notch.rb"
RELEASE_REPO="ProMeX04/notch-releases"
APP_REPO="ProMeX04/notch-app"
ZIP_PATH="$ROOT_DIR/dist/Notch-$VERSION.zip"

cd "$ROOT_DIR"

if [[ ! -f "$CASK_FILE" ]]; then
    echo "Missing cask file: $CASK_FILE" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain -- ':!/.claude/settings.json')" ]]; then
    echo "App repo has uncommitted changes. Commit or stash them first." >&2
    git status --short
    exit 1
fi

if [[ -n "$(git -C "$TAP_DIR" status --porcelain)" ]]; then
    echo "Homebrew tap has uncommitted changes. Commit or stash them first." >&2
    git -C "$TAP_DIR" status --short
    exit 1
fi

CURRENT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist")"
CASK_VERSION="$(ruby -ne 'puts $1 if /version "([^"]+)"/' "$CASK_FILE")"

if [[ "$CASK_VERSION" == "$VERSION" ]]; then
    echo "Cask is already at version $VERSION. Pick a new version to avoid overwriting release assets." >&2
    exit 1
fi

if gh release view "v$VERSION" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    echo "GitHub release v$VERSION already exists. Pick a new version." >&2
    exit 1
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$ROOT_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$ROOT_DIR/Info.plist"

RELEASE=1 "$ROOT_DIR/build-app.sh"

rm -f "$ZIP_PATH"
ditto -c -k --keepParent "$ROOT_DIR/dist/Notch.app" "$ZIP_PATH"
SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

ruby -0pi -e "gsub(/version \"[^\"]+\"/, 'version \"$VERSION\"'); gsub(/sha256 \"[^\"]+\"/, 'sha256 \"$SHA256\"')" "$CASK_FILE"

git add Info.plist
git commit -m "chore: bump version to $VERSION

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

git -C "$TAP_DIR" add notch.rb
git -C "$TAP_DIR" commit -m "chore: bump notch to $VERSION

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"

if [[ "$PUBLISH" == "1" ]]; then
    gh release create "v$VERSION" "$ZIP_PATH" --repo "$RELEASE_REPO" --title "Notch $VERSION" --notes "Release $VERSION"
    git push origin main
    git -C "$TAP_DIR" push origin main
    echo "Published Notch $VERSION to GitHub releases and Homebrew tap."
else
    echo "Prepared Notch $VERSION release."
    echo "Zip: $ZIP_PATH"
    echo "sha256: $SHA256"
    echo "Run with --publish to create GitHub release and push repos."
fi

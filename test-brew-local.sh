#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Info.plist" 2>/dev/null || echo "1.0.1")"
ZIP_NAME="Notch-${VERSION}.zip"
ZIP_PATH="$ROOT_DIR/dist/$ZIP_NAME"

echo "==> Building App..."
"$ROOT_DIR/build-app.sh"

echo "==> Creating release ZIP using ditto (preserves symlinks & attributes)..."
# Using ditto is CRITICAL. zip -r can break macOS app bundle structure, causing bundle/framework errors.
ditto -c -k --keepParent "$ROOT_DIR/dist/Notch.app" "$ZIP_PATH"

SHA256=$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')
echo "==> ZIP created: $ZIP_PATH"
echo "==> SHA256: $SHA256"

# Apply test values to local brew formula
CASK_PATH="/opt/homebrew/Library/Taps/promex04/homebrew-tap/Casks/notch.rb"
if [[ -f "$CASK_PATH" ]]; then
    echo "==> Updating Brew Cask for local testing..."
    # Make a backup
    cp "$CASK_PATH" "${CASK_PATH}.bak"
    
    # Update URL and SHA in the ruby file
    sed -i '' "s|url \".*\"|url \"file://$ZIP_PATH\"|" "$CASK_PATH"
    sed -i '' "s|sha256 \".*\"|sha256 \"$SHA256\"|" "$CASK_PATH"
    
    # Optional: ensure no_quarantine is there if we get damaged app errors
    if ! grep -q "no_quarantine" "$CASK_PATH"; then
      # Add no_quarantine true before `app "Notch.app"` if we don't code sign with Developer ID.
      echo "Note: If you get 'App is damaged' errors, add 'require \"cask/download_strategy\"' or 'quarantine false' based on brew version."
    fi

    echo "==> Running brew install from local ZIP..."
    /opt/homebrew/bin/brew reinstall --cask "$CASK_PATH"
    
    echo "==> Reverting Cask file to original URL..."
    mv "${CASK_PATH}.bak" "$CASK_PATH"
    
    echo "==> Test installation complete! Open /Applications/Notch.app to test if the bundle error is fixed."
else
    echo "==> Could not find local cask at $CASK_PATH"
fi

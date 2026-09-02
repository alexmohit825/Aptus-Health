#!/usr/bin/env bash
# =============================================================================
#  generate.sh — produce Aptus.xcodeproj from project.yml using XcodeGen.
#
#  Run on your Mac:   cd ios && ./generate.sh
#
#  This regenerates the full Xcode project in ~1 second. Re-run it whenever you
#  add/rename Swift files or change capabilities, bundle IDs, or deployment
#  targets in project.yml. Never edit Aptus.xcodeproj by hand — edit project.yml.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "xcodegen not found — installing via Homebrew (one time)..."
  brew install xcodegen
fi

echo "▸ Generating Aptus.xcodeproj from project.yml..."
xcodegen generate

echo ""
echo "✓ Done. Open Aptus.xcodeproj in Xcode."
echo "  1. Set DEVELOPMENT_TEAM in project.yml (or Xcode → Signing & Capabilities)."
echo "  2. Select the 'Aptus' scheme (NOT the Watch-only scheme)."
echo "  3. Choose a paired 'iPhone + Apple Watch Ultra' destination."
echo "  4. Run (⌘R). Xcode installs both the iPhone app and the Watch companion."

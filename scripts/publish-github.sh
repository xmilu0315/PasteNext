#!/bin/zsh
# One-shot publish: pushes the source to GitHub and publishes the DMG as a
# release asset.
#
# Requires a Personal Access Token with the `repo` scope:
#   https://github.com/settings/tokens
#   → Fine-grained tokens: Repository permissions → Contents: Read & write
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx ./scripts/publish-github.sh [version] [--public]
#
# Without --public the repository stays private.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${GITHUB_OWNER:-xmilu0315}"
REPO="${GITHUB_REPO:-PasteNext}"
REMOTE="https://github.com/$OWNER/$REPO.git"

VERSION="${1:-}"
[ -z "$VERSION" ] && VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"

if [ -z "${GITHUB_TOKEN:-}" ]; then
    print -u2 "error: GITHUB_TOKEN is not set"
    print -u2 "  create a token at https://github.com/settings/tokens with the 'repo' scope, then:"
    print -u2 "    GITHUB_TOKEN=ghp_xxx $0 $VERSION"
    exit 1
fi

cd "$ROOT"

# ---- 1. source code --------------------------------------------------
if [ -d .git ]; then
    print "==> pushing source to $REMOTE"
    git add -A
    if git diff --cached --quiet; then
        print "   nothing new to commit"
    else
        git commit -q -m "Publish PasteNext $VERSION"
    fi
    # The token is used only for this push and is not stored on disk.
    git -c "credential.helper=" -c "core.askPass=true" \
        push -u "$REMOTE" main 2>&1 | sed 's/^/   /' || {
        # askPass is not portable; fall back to the URL with the token inline.
        print "   retrying with an inline credential..."
        git push -u "https://x-access-token:$GITHUB_TOKEN@github.com/$OWNER/$REPO.git" main 2>&1 | sed 's/^/   /'
    }
else
    print -u2 "error: $ROOT is not a git repository"
    exit 1
fi

# ---- 2. release + DMG asset -----------------------------------------
print "==> publishing the release"
GITHUB_TOKEN="$GITHUB_TOKEN" "$ROOT/scripts/release-github.sh" "$VERSION" "${@:2}"

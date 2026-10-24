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
    # The token is passed through GIT_ASKPASS, so it never appears in the
    # command line, in .git/config or in ~/.git-credentials.
    ASKPASS="$(mktemp -t pastenext-askpass).XXXXXX"
    cat > "$ASKPASS" <<'ASK'
#!/bin/sh
case "$1" in
    *sername*) echo "x-access-token" ;;
    *)         echo "$GITHUB_TOKEN" ;;
esac
ASK
    chmod +x "$ASKPASS"
    GIT_ASKPASS="$ASKPASS" GIT_TERMINAL_PROMPT=0 \
        git -c "credential.helper=" push -u "$REMOTE" main 2>&1 | sed 's/^/   /'
    rm -f "$ASKPASS"
else
    print -u2 "error: $ROOT is not a git repository"
    exit 1
fi

# ---- 2. release + DMG asset -----------------------------------------
print "==> publishing the release"
GITHUB_TOKEN="$GITHUB_TOKEN" "$ROOT/scripts/release-github.sh" "$VERSION" "${@:2}"

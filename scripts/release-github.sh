#!/bin/zsh
# Publishes PasteNext to GitHub: creates the release and attaches the built
# DMG so people can download it from the repo page.
#
# Requires a Personal Access Token with the `repo` scope:
#   https://github.com/settings/tokens
#   → Fine-grained tokens: Repository permissions → Contents: Read & write
#
# Usage:
#   GITHUB_TOKEN=ghp_xxx ./scripts/release-github.sh [version] [--public]
#
# Without --public the repository is kept private, which is what you want
# while the app is still being sold.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWNER="${GITHUB_OWNER:-xmilu0315}"
REPO="${GITHUB_REPO:-PasteNext}"
API="https://api.github.com"

VERSION="${1:-}"
[ -z "$VERSION" ] && VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
TAG="v$VERSION"
DMG="$ROOT/Dist/PasteNext-$VERSION.dmg"

MAKE_PUBLIC=0
for a in "$@"; do
    [ "$a" = "--public" ] && MAKE_PUBLIC=1
done

if [ -z "${GITHUB_TOKEN:-}" ]; then
    print -u2 "error: GITHUB_TOKEN is not set"
    print -u2 "  create a token at https://github.com/settings/tokens with the 'repo' scope, then:"
    print -u2 "    GITHUB_TOKEN=ghp_xxx $0 $VERSION"
    exit 1
fi

if [ ! -f "$DMG" ]; then
    print -u2 "error: $DMG not found — run ./scripts/build-app.sh first"
    exit 1
fi

auth=(-H "Authorization: Bearer $GITHUB_TOKEN" -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")

print "==> repository visibility"
if [ "$MAKE_PUBLIC" = "1" ]; then
    curl -sS -X PATCH "${auth[@]}" "$API/repos/$OWNER/$REPO" \
        -d "{\"private\":false,\"description\":\"原生 macOS 剪贴板历史管理器 · SwiftUI + AppKit · 零第三方依赖\"}" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print('   visibility =', d.get('visibility'), '| private =', d.get('private'))"
else
    curl -sS -X PATCH "${auth[@]}" "$API/repos/$OWNER/$REPO" \
        -d "{\"private\":true,\"description\":\"原生 macOS 剪贴板历史管理器 · SwiftUI + AppKit · 零第三方依赖\"}" \
        | python3 -c "import json,sys; d=json.load(sys.stdin); print('   visibility =', d.get('visibility'), '| private =', d.get('private'))"
fi

print "==> tag $TAG"
# Create the tag if it does not exist yet.
if ! curl -sS -f "${auth[@]}" "$API/repos/$OWNER/$REPO/git/ref/tags/$TAG" >/dev/null 2>&1; then
    SHA=$(curl -sS "${auth[@]}" "$API/repos/$OWNER/$REPO/commits/main" | python3 -c "import json,sys; print(json.load(sys.stdin)['sha'])")
    curl -sS -X POST "${auth[@]}" "$API/repos/$OWNER/$REPO/git/refs" \
        -d "{\"ref\":\"refs/tags/$TAG\",\"sha\":\"$SHA\"}" >/dev/null
    print "   created tag $TAG -> ${SHA:0:8}"
else
    print "   tag $TAG already exists"
fi

print "==> release $TAG"
BODY=$(cat <<'MD'
## PasteNext $VERSION

原生 macOS 剪贴板历史管理器 —— 轻量轮询、仅在变化时读取、自动分类、随手贴回。

**下载：** 下方的 `PasteNext-$VERSION.dmg`（通用二进制，Apple Silicon 与 Intel 均可运行）

**安装：** 双击 DMG，把 PasteNext 拖进「应用程序」即可。需要 macOS 13 或更高版本。

**首次使用：** 在「系统设置 → 隐私与安全性 → 辅助功能」中授权 PasteNext，即可自动粘贴（⌘V）。仅唤出窗口查看历史无需该权限。

**功能：** 智能分类（六类内容自动识别）· 全键盘操作 · 唤出不抢焦点 · 全格式文件原样粘贴 · 标签分类 · 批量整理 · 预览编辑 · 隐私优先 · 通用剪贴板（接力）

**隐私：** 不设密码、不上云、不联网，历史仅保存在本机，后台网络请求 0 次。
MD
)
BODY=$(printf '%s' "$BODY" | sed "s/\$VERSION/$VERSION/g")

PAYLOAD=$(python3 - "$VERSION" "$TAG" "$BODY" <<'PY'
import json, sys
version, tag, body = sys.argv[1], sys.argv[2], sys.argv[3]
print(json.dumps({
    "tag_name": tag,
    "name": f"PasteNext {version}",
    "body": body,
    "draft": False,
    "prerelease": False,
}))
PY
)

EXISTING=$(curl -sS "${auth[@]}" "$API/repos/$OWNER/$REPO/releases/tags/$TAG" \
    | python3 -c "import json,sys
try:
    print(json.load(sys.stdin).get('id',''))
except Exception:
    print('')")

if [ -n "$EXISTING" ]; then
    print "   release already exists (id=$EXISTING) — replacing the asset"
    RELEASE_ID="$EXISTING"
    # Drop the old asset so the new DMG does not show up twice.
    for aid in $(curl -sS "${auth[@]}" "$API/repos/$OWNER/$REPO/releases/$RELEASE_ID/assets" \
                 | python3 -c "import json,sys
try:
    print(' '.join(str(a['id']) for a in json.load(sys.stdin)))
except Exception:
    print('')"); do
        curl -sS -X DELETE "${auth[@]}" "$API/repos/$OWNER/$REPO/releases/assets/$aid" >/dev/null || true
    done
else
    RELEASE_ID=$(curl -sS -X POST "${auth[@]}" "$API/repos/$OWNER/$REPO/releases" -d "$PAYLOAD" \
        | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
    print "   created release (id=$RELEASE_ID)"
fi

if [ -z "$RELEASE_ID" ]; then
    print -u2 "error: could not create the release"
    exit 1
fi

print "==> uploading $(basename "$DMG")"
# The asset upload goes to uploads.github.com; the exact URL is taken from the
# release's own upload_url so it can never drift.
UPLOAD_URL=$(curl -sS "${auth[@]}" "$API/repos/$OWNER/$REPO/releases/$RELEASE_ID" \
    | python3 -c "import json,sys
u = json.load(sys.stdin).get('upload_url','')
print(u.split('{')[0])")
[ -z "$UPLOAD_URL" ] && UPLOAD_URL="https://uploads.github.com/repos/$OWNER/$REPO/releases/$RELEASE_ID/assets"
curl -sS -X POST "${auth[@]}" \
    -H "Content-Type: application/octet-stream" \
    --data-binary "@$DMG" \
    "$UPLOAD_URL?name=$(basename "$DMG")" \
    | python3 -c "import json,sys
d = json.load(sys.stdin)
print('   asset:', d.get('name'), '| size:', d.get('size'), 'bytes')
print('   download:', d.get('browser_download_url'))
if d.get('id') is None:
    print('   ERROR:', d.get('message'))
    raise SystemExit(1)"

print ""
print "done: https://github.com/$OWNER/$REPO/releases/tag/$TAG"

#!/bin/bash
# 发一个新版本到 GitHub Release，分核对和发布两步：
#   1. 改 project.yml 的 MARKETING_VERSION 和 CURRENT_PROJECT_VERSION（构建号要比上一版大），xcodegen generate，
#      提交推到 main，打 tag v<版本> 推上去
#   2. 等这个 tag 的 CI（.github/workflows/build.yml）跑完、通过
#   3. bash scripts/release.sh：核对代码和 tag 对得上、这个 tag 的 CI 过了（scripts/ci_passed.sh），
#      用 RELEASE=1 bash build.sh 编出 Developer ID 签名的通用包，打出 dmg 和 zip（带版本号的一份 + 固定名 AskFree.dmg / AskFree.zip 一份），
#      逐个核对签名；给带版本号的 zip 生成并签名自动更新用的 appcast.xml（scripts/make_appcast.sh，私钥从 dispatch env 取）；
#      算 SHA-256，记进 release/<版本>/checked.json。第一次跑时从 docs/release-notes-template.md 复制出 release/<版本>/notes.md
#   4. 把 notes.md 里的【待填】都写好（release/ 不进 git，不会挡住「工作区干净」的检查），看过没问题：
#      bash scripts/release.sh --publish：只上传第 3 步核对过、SHA-256 没变的文件，建 Release（不是草稿）
# 固定名的文件让 README 和官网能一直链到最新版，装着的 Ask Free 也从固定名的 appcast.xml 查新版本：
#   https://github.com/SchaeferAnjon/askfree/releases/latest/download/AskFree.dmg
#   https://github.com/SchaeferAnjon/askfree/releases/latest/download/appcast.xml
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="SchaeferAnjon/askfree"
TEAM_ID="3H5S5NXPXS" # 和 build.sh 里的一样：装着的正式版就是这个团队签的
case "${1:-}" in
    --publish) PUBLISH=1 ;;
    "") PUBLISH=0 ;;
    *) echo "用法：bash scripts/release.sh [--publish]" >&2; exit 2 ;;
esac

fail() {
    echo "没发：$1" >&2
    exit 1
}

cd "$ROOT_DIR"
yml_value() { sed -n "s/^ *$1: *\"\{0,1\}\([^\"]*\)\"\{0,1\} *$/\1/p" | head -1; }
VERSION="$(yml_value MARKETING_VERSION <project.yml)"
BUILD="$(yml_value CURRENT_PROJECT_VERSION <project.yml)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "project.yml 里的 MARKETING_VERSION 不是 x.y.z：$VERSION"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "project.yml 里的 CURRENT_PROJECT_VERSION 不是整数：$BUILD"
TAG="v$VERSION"
OUT="$ROOT_DIR/release/$VERSION"
NOTES="$OUT/notes.md"
CHECKED="$OUT/checked.json"
APP="$ROOT_DIR/dist/Ask Free.app"

# 代码和 tag 对得上：工作区干净，tag 已经推上去了、指的就是 HEAD，构建号比上一版大，GitHub 上还没有这个 Release
[ -z "$(git status --porcelain)" ] || fail "工作区有没提交的改动（git status 看）"
HEAD_SHA="$(git rev-parse HEAD)"
REMOTE_TAG="$(git ls-remote --tags origin "refs/tags/$TAG" "refs/tags/$TAG^{}")"
[ -n "$REMOTE_TAG" ] || fail "origin 上还没有 $TAG：先 git tag $TAG && git push origin $TAG"
# 带注释的 tag 有一行 ^{}，那一行才是它指的提交
TAG_SHA="$(awk '/\^\{\}$/ { print $1; found = 1 } END { if (!found) print "" }' <<<"$REMOTE_TAG")"
[ -n "$TAG_SHA" ] || TAG_SHA="$(awk 'NR == 1 { print $1 }' <<<"$REMOTE_TAG")"
[ "$TAG_SHA" = "$HEAD_SHA" ] || fail "$TAG 指的是 ${TAG_SHA:0:7}，本机 HEAD 是 ${HEAD_SHA:0:7}"
PREV_TAG="$(git tag -l 'v*' --sort=-v:refname | grep -vxF "$TAG" | head -1 || true)"
if [ -n "$PREV_TAG" ]; then
    PREV_BUILD="$(git show "$PREV_TAG:project.yml" | yml_value CURRENT_PROJECT_VERSION)"
    [[ "$PREV_BUILD" =~ ^[0-9]+$ ]] || fail "读不出 $PREV_TAG 的构建号：$PREV_BUILD"
    [ "$BUILD" -gt "$PREV_BUILD" ] || fail "构建号 $BUILD 没比上一版 $PREV_TAG 的 $PREV_BUILD 大：改 project.yml 的 CURRENT_PROJECT_VERSION"
fi
if GH_OUT="$(gh release view "$TAG" -R "$REPO" --json tagName 2>&1)"; then
    fail "GitHub 上已经有 $TAG 的 Release"
elif [[ "$GH_OUT" != *"release not found"* ]]; then
    fail "查不了 GitHub 上有没有 $TAG 的 Release：$GH_OUT"
fi

sha256() { shasum -a 256 "$1" | awk '{ print $1 }'; }

if [ "$PUBLISH" = "1" ]; then
    # 只上传核对过的那一份，不重新打包
    [ -f "$CHECKED" ] || fail "还没核对：先跑 bash scripts/release.sh"
    [ "$(plutil -extract head raw -o - "$CHECKED")" = "$HEAD_SHA" ] || fail "$OUT 不是这个提交核对过的：先跑 bash scripts/release.sh"
    [ -f "$NOTES" ] || fail "还没写发布说明：$NOTES"
    grep -q "【待填" "$NOTES" && fail "发布说明里还有【待填】：$NOTES"
    FILES=()
    COUNT="$(plutil -extract files raw -o - "$CHECKED")"
    for ((i = 0; i < COUNT; i++)); do
        name="$(plutil -extract "files.$i.name" raw -o - "$CHECKED")"
        want="$(plutil -extract "files.$i.sha256" raw -o - "$CHECKED")"
        [ -f "$OUT/$name" ] || fail "核对过的文件不见了：$OUT/$name"
        [ "$(sha256 "$OUT/$name")" = "$want" ] || fail "$name 核对后被改过（SHA-256 对不上）：重新跑 bash scripts/release.sh"
        FILES+=("$OUT/$name")
    done
    gh release create "$TAG" -R "$REPO" --verify-tag --title "Ask Free $VERSION" --notes-file "$NOTES" "${FILES[@]}"
    echo "已发布 $TAG：https://github.com/$REPO/releases/tag/$TAG"
    exit 0
fi

# 这个 tag 的 CI（单元测试、编译、启动自测）跑完并且通过了才编正式包
bash "$ROOT_DIR/scripts/ci_passed.sh" "$TAG" || fail "$TAG 的 CI 没过（上面一行是原因）"

# 写好的发布说明留着，其余重新来
KEPT_NOTES=""
[ -f "$NOTES" ] && KEPT_NOTES="$(cat "$NOTES")"
rm -rf "$OUT"
mkdir -p "$OUT"
if [ -n "$KEPT_NOTES" ]; then
    printf '%s\n' "$KEPT_NOTES" >"$NOTES"
else
    # 模板开头的用法注释不带过去
    sed -e '/^<!--/,/^-->/d' -e "s/{{VERSION}}/$VERSION/g" "$ROOT_DIR/docs/release-notes-template.md" >"$NOTES"
fi

RELEASE=1 bash "$ROOT_DIR/build.sh"
# build.sh 会用 xcodegen 重新生成工程：生成出来和提交的不一样，说明编的不是 tag 上的那份代码
[ -z "$(git status --porcelain)" ] || fail "编完工作区变了（多半是 project.yml 改了没重新生成 AskFree.xcodeproj）：$(git status --porcelain | head -3)"
PLIST="$APP/Contents/Info.plist"
[ "$(plutil -extract CFBundleShortVersionString raw -o - "$PLIST")" = "$VERSION" ] || fail "编出来的版本号不是 $VERSION"
[ "$(plutil -extract CFBundleVersion raw -o - "$PLIST")" = "$BUILD" ] || fail "编出来的构建号不是 $BUILD"

# shellcheck disable=SC1091
. "$ROOT_DIR/local.build.env"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/askfree-release.XXXXXX")"
trap 'hdiutil detach "$WORK/mnt" -quiet 2>/dev/null || true; rm -rf "$WORK"' EXIT

# 一个包里的 App 签名对不对：能通过严格校验，Developer ID、团队号对，两种芯片都在，版本号是这一版
check_app() {
    local app="$1" label="$2" info archs
    codesign --verify --deep --strict "$app" || fail "$label 里的 App 签名校验没过"
    info="$(codesign -dvv "$app" 2>&1)"
    grep -q "^Authority=Developer ID Application:" <<<"$info" && grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$info" \
        || fail "$label 里的 App 不是团队 $TEAM_ID 的 Developer ID 签的"
    archs=" $(lipo -archs "$app/Contents/MacOS/AskFree") "
    [[ "$archs" == *" arm64 "* && "$archs" == *" x86_64 "* ]] || fail "$label 里的 App 不是 arm64 + x86_64 通用包（$archs）"
    [ "$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")" = "$VERSION" ] || fail "$label 里的 App 版本号不对"
}

ZIP="$OUT/AskFree-$VERSION.zip"
DMG="$OUT/AskFree-$VERSION.dmg"
echo "打 zip…"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ditto -x -k "$ZIP" "$WORK/unzip"
check_app "$WORK/unzip/Ask Free.app" "$(basename "$ZIP")"

# dmg：打开后左边 App、右边「应用程序」的替身，拖过去就装好，不会在「下载」里直接运行
echo "打 dmg…"
mkdir -p "$WORK/dmg"
ditto "$APP" "$WORK/dmg/Ask Free.app"
ln -s /Applications "$WORK/dmg/Applications"
hdiutil create -quiet -volname "Ask Free" -srcfolder "$WORK/dmg" -fs HFS+ -format UDZO -ov "$DMG"
codesign --sign "$DEVELOPER_ID_IDENTITY" --timestamp "$DMG"
codesign --verify --strict "$DMG" || fail "dmg 的签名校验没过"
DMG_INFO="$(codesign -dvv "$DMG" 2>&1)"
grep -q "^Authority=Developer ID Application:" <<<"$DMG_INFO" && grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$DMG_INFO" \
    || fail "dmg 不是团队 $TEAM_ID 的 Developer ID 签的"
grep -q "^Timestamp=" <<<"$DMG_INFO" || fail "dmg 的签名里没有安全时间戳"
hdiutil verify -quiet "$DMG" || fail "dmg 校验没过（hdiutil verify）"
hdiutil attach -quiet -nobrowse -readonly -noautoopen -mountpoint "$WORK/mnt" "$DMG"
check_app "$WORK/mnt/Ask Free.app" "$(basename "$DMG")"
[ "$(readlink "$WORK/mnt/Applications")" = "/Applications" ] || fail "dmg 里没有指向 /Applications 的替身"
hdiutil detach -quiet "$WORK/mnt"

# 自动更新：给带版本号的 zip 生成并签名 appcast.xml（Sparkle 装更新用的是 zip），下载地址指向这个 Release 里的那份 zip
echo "生成 appcast.xml…"
APPCAST="$OUT/appcast.xml"
bash "$ROOT_DIR/scripts/make_appcast.sh" "$ZIP" "$APPCAST"
ZIP_URL="https://github.com/$REPO/releases/download/$TAG/$(basename "$ZIP")"
grep -qF "url=\"$ZIP_URL\"" "$APPCAST" || fail "appcast.xml 里的下载地址不是 $ZIP_URL"
grep -qF "length=\"$(stat -f %z "$ZIP")\"" "$APPCAST" || fail "appcast.xml 里的大小和 $(basename "$ZIP") 对不上"
grep -qF "<sparkle:version>$BUILD</sparkle:version>" "$APPCAST" || fail "appcast.xml 里的构建号不是 $BUILD"

# 不带版本号的两份：README 和官网链到 releases/latest/download/<文件名>，点一下就开始下载最新版
cp "$DMG" "$OUT/AskFree.dmg"
cp "$ZIP" "$OUT/AskFree.zip"

NAMES=("AskFree-$VERSION.dmg" "AskFree-$VERSION.zip" "AskFree.dmg" "AskFree.zip" "appcast.xml")
{
    printf '{\n "version": "%s",\n "build": "%s",\n "tag": "%s",\n "head": "%s",\n "files": [\n' "$VERSION" "$BUILD" "$TAG" "$HEAD_SHA"
    for i in "${!NAMES[@]}"; do
        f="$OUT/${NAMES[$i]}"
        sep=","
        [ "$i" -eq $((${#NAMES[@]} - 1)) ] && sep=""
        printf '  {"name": "%s", "bytes": %s, "sha256": "%s"}%s\n' "${NAMES[$i]}" "$(stat -f %z "$f")" "$(sha256 "$f")" "$sep"
    done
    printf ' ]\n}\n'
} >"$CHECKED"

echo
echo "$TAG 要上传的文件（$OUT）："
for name in "${NAMES[@]}"; do
    printf '  %-22s %5.1f MB  sha256 %s\n' "$name" "$(echo "$(stat -f %z "$OUT/$name") / 1000000" | bc -l)" "$(sha256 "$OUT/$name")"
done
echo
if grep -q "【待填" "$NOTES"; then
    echo "核对过了，还没上传。把发布说明 $NOTES 里的【待填】写好，确认后：bash scripts/release.sh --publish"
else
    echo "核对过了，还没上传。发布说明在 $NOTES，确认后：bash scripts/release.sh --publish"
fi

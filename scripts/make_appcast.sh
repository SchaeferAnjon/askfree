#!/bin/bash
# 给发版用：为一个打好的更新包（AskFree-<版本>.zip）生成并签名 Sparkle 的 appcast.xml。
# 装着的 Ask Free 每 6 小时查一次 https://github.com/SchaeferAnjon/askfree/releases/latest/download/appcast.xml，
# 所以 appcast.xml 要和 zip 一起传到同一个 Release，文件名固定叫 appcast.xml。
#
# 用法：
#   bash scripts/make_appcast.sh <AskFree-版本.zip> [输出的 appcast.xml]
#   输出不写就放在 zip 旁边：<zip 所在目录>/appcast.xml
# 环境变量（都可以不设）：
#   ASKFREE_SPARKLE_PRIVATE_KEY  签名私钥（EdDSA）；不设就用 dispatch env get ASKFREE_SPARKLE_PRIVATE_KEY 取，绝不打印
#   APPCAST_DOWNLOAD_URL         zip 的下载地址；默认 https://github.com/SchaeferAnjon/askfree/releases/download/v<版本>/<zip 文件名>
#   SPARKLE_BIN                  Sparkle 的 sign_update 所在目录；默认在 build.sh 编译用的 DerivedData 里找
#   DERIVED_DATA_PATH            和 build.sh 同一个变量，默认 /private/tmp/askfree-release-dd
#
# 做的事：从 zip 里的 App 读版本号、构建号、最低系统、芯片和 SUPublicEDKey；核对私钥和 SUPublicEDKey 是一对；
# 用 sign_update 给 zip 签名，写 appcast（只有这一版一项），再给 appcast 本身签名（Info.plist 里开了 SURequireSignedFeed）。
set -euo pipefail

REPO="SchaeferAnjon/askfree"
fail() {
    echo "没生成 appcast：$1" >&2
    exit 1
}

[ $# -ge 1 ] && [ $# -le 2 ] || { echo "用法：bash scripts/make_appcast.sh <AskFree-版本.zip> [输出的 appcast.xml]" >&2; exit 2; }
ZIP="$1"
[ -f "$ZIP" ] || fail "找不到 $ZIP"
ZIP="$(cd "$(dirname "$ZIP")" && pwd)/$(basename "$ZIP")"
OUT="${2:-$(dirname "$ZIP")/appcast.xml}"

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/askfree-release-dd}"
SPARKLE_BIN="${SPARKLE_BIN:-$DERIVED_DATA_PATH/SourcePackages/artifacts/sparkle/Sparkle/bin}"
SIGN_UPDATE="$SPARKLE_BIN/sign_update"
[ -x "$SIGN_UPDATE" ] || fail "找不到 Sparkle 的 sign_update（$SIGN_UPDATE）：先用 build.sh 编一次，或者设 SPARKLE_BIN"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/askfree-appcast.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# 读 zip 里的 App
ditto -x -k "$ZIP" "$WORK/unzip"
APPS=("$WORK"/unzip/*.app)
[ ${#APPS[@]} -eq 1 ] && [ -d "${APPS[0]}" ] || fail "$ZIP 里应该正好有一个 .app"
APP="${APPS[0]}"
PLIST="$APP/Contents/Info.plist"
read_plist() { plutil -extract "$1" raw -o - "$PLIST" 2>/dev/null || true; }
VERSION="$(read_plist CFBundleShortVersionString)"
BUILD="$(read_plist CFBundleVersion)"
MIN_OS="$(read_plist LSMinimumSystemVersion)"
PUBLIC_KEY="$(read_plist SUPublicEDKey)"
EXECUTABLE="$(read_plist CFBundleExecutable)"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "App 的版本号不是 x.y.z：$VERSION"
[[ "$BUILD" =~ ^[0-9]+$ ]] || fail "App 的构建号不是整数：$BUILD"
[[ "$MIN_OS" =~ ^[0-9]+(\.[0-9]+)*$ ]] || fail "App 的 LSMinimumSystemVersion 不对：$MIN_OS"
[ -n "$PUBLIC_KEY" ] || fail "App 的 Info.plist 里没有 SUPublicEDKey：这个包不会自动更新"
ARCHS=" $(lipo -archs "$APP/Contents/MacOS/$EXECUTABLE") "
[[ "$ARCHS" == *" arm64 "* ]] || fail "App 里没有 arm64（$ARCHS）"
HARDWARE=""
# 只有 Apple 芯片版时，别让 Intel Mac 下到装不上的包
[[ "$ARCHS" == *" x86_64 "* ]] || HARDWARE="      <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"

# 私钥：只在管道里传，不落盘、不打印
KEY="${ASKFREE_SPARKLE_PRIVATE_KEY:-}"
if [ -z "$KEY" ]; then
    command -v dispatch >/dev/null 2>&1 || fail "没设 ASKFREE_SPARKLE_PRIVATE_KEY，也没有 dispatch 命令取它"
    KEY="$(dispatch env get ASKFREE_SPARKLE_PRIVATE_KEY 2>/dev/null || true)"
fi
KEY="$(printf '%s' "$KEY" | tr -d '[:space:]')"
[ -n "$KEY" ] || fail "取不到签名私钥 ASKFREE_SPARKLE_PRIVATE_KEY（dispatch env list -P askfree 看有没有）"

# 私钥和 App 里的公钥是一对，不然装着的 App 会拒收这个更新
DERIVED_PUBLIC="$(printf '%s\n' "$KEY" | swift -e 'import CryptoKit; import Foundation
guard let line = readLine(), let seed = Data(base64Encoded: line),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { exit(1) }
print(key.publicKey.rawRepresentation.base64EncodedString())' 2>/dev/null)" || fail "签名私钥的格式不对（要 generate_keys -x 导出的那种）"
[ "$DERIVED_PUBLIC" = "$PUBLIC_KEY" ] || fail "签名私钥和 App 里的 SUPublicEDKey 不是一对"

ENCLOSURE="$(printf '%s\n' "$KEY" | "$SIGN_UPDATE" --ed-key-file - "$ZIP")" || fail "sign_update 给 zip 签名失败"
[[ "$ENCLOSURE" =~ ^sparkle:edSignature=\"[A-Za-z0-9+/=]+\"\ length=\"[0-9]+\"$ ]] || fail "sign_update 的输出看不懂：$ENCLOSURE"

URL="${APPCAST_DOWNLOAD_URL:-https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ZIP")}"
[[ "$URL" =~ ^https?://[^[:space:]\"\<\>]+$ ]] || fail "下载地址不对：$URL"
URL="${URL//&/&amp;}"
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"

mkdir -p "$(dirname "$OUT")"
cat >"$OUT" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Ask Free</title>
    <link>https://github.com/$REPO/releases</link>
    <item>
      <title>Ask Free $VERSION</title>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <pubDate>$PUB_DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
$HARDWARE
      <enclosure url="$URL" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
XML
# 没有 hardwareRequirements 那一行时会留一行空行，删掉
sed -i '' '/^$/d' "$OUT"
xmllint --noout "$OUT" || fail "写出来的 $OUT 不是合法的 XML"

# appcast 本身也签上（签名写进文件末尾的注释里）
printf '%s\n' "$KEY" | "$SIGN_UPDATE" --ed-key-file - "$OUT" >/dev/null || fail "sign_update 给 appcast 签名失败"
grep -q "sparkle-signatures" "$OUT" || fail "appcast 里没写进签名"

echo "appcast：$OUT"
echo "  Ask Free $VERSION（构建号 $BUILD），macOS $MIN_OS 起，芯片：${ARCHS:1:${#ARCHS}-2}"
echo "  下载地址：${URL//&amp;/&}"
echo "  和 $(basename "$ZIP") 一起传到 v$VERSION 的 Release，文件名就叫 appcast.xml"

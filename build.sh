#!/bin/bash
# 编译 Release 版 Ask Free（arm64 + x86_64 通用包，Apple 芯片和 Intel 芯片的 Mac 都能用），产物在 dist/Ask Free.app。
# 有 Developer ID 证书（local.build.env 里的 DEVELOPER_ID_IDENTITY）就用它签名，没有就 ad hoc 签名，自己用足够。
#
# 发版模式 RELEASE=1 bash build.sh（scripts/release.sh 用它）：找不到 Developer ID 证书就停，不出临时签名的包；
# 编完核对签名是团队 TEAM_ID 的 Developer ID、带苹果的安全时间戳、没有调试权限，不对就报错。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/AskFree.xcodeproj"
# 不放 ~/Documents 下：那里的 iCloud 扩展属性会让 codesign 失败
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/askfree-release-dd}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/Ask Free.app"
APP_DIR="$ROOT_DIR/dist/Ask Free.app"
RELEASE="${RELEASE:-0}"
# 装着的正式版就是这个团队的 Developer ID 签的：换团队签，用户的辅助功能、屏幕录制权限和钥匙串里的 Key 都要重给
TEAM_ID="3H5S5NXPXS"

fail() {
    echo "❌ $1" >&2
    exit 1
}

if [ -f "$ROOT_DIR/local.build.env" ]; then
    # shellcheck disable=SC1091
    . "$ROOT_DIR/local.build.env"
fi
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"

# 改过 project.yml 又装了 xcodegen：先重新生成工程
if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && xcodegen generate --quiet)
fi

if [ -n "$DEVELOPER_ID_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$DEVELOPER_ID_IDENTITY\""; then
    SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY"
elif [ "$RELEASE" = "1" ]; then
    fail "发版模式要 Developer ID 证书签名：local.build.env 里的 DEVELOPER_ID_IDENTITY 没填，或者钥匙串里没有这张证书（security find-identity -v -p codesigning 看有哪些）"
else
    SIGN_IDENTITY="-"
fi
if [ "$RELEASE" = "1" ] && [[ "$SIGN_IDENTITY" != "Developer ID Application:"* ]]; then
    fail "发版要用「Developer ID Application」证书，现在是：$SIGN_IDENTITY"
fi
# 临时签名（ad hoc）的包不开 hardened runtime：开了的话系统的库校验要求 App 和 Sparkle.framework 是同一个团队签的，
# 临时签名没有团队号，App 一启动就因为加载不了 Sparkle 退出。Developer ID 签的包照常开
HARDENED_RUNTIME=YES
[ "$SIGN_IDENTITY" = "-" ] && HARDENED_RUNTIME=NO

# 安全时间戳要连苹果的时间戳服务器，ad hoc 签名不支持
SIGN_FLAGS=""
[ "$SIGN_IDENTITY" != "-" ] && SIGN_FLAGS="--timestamp"
# 签名一律 Manual、团队号照证书给：Swift 包里的资源包（公式字体那个 SwiftMath_SwiftMath）默认走自动签名，
# 不给团队号会报「requires a development team」
SIGN_TEAM=""
[ "$SIGN_IDENTITY" != "-" ] && SIGN_TEAM="$TEAM_ID"
# 发版先清掉上次的编译结果再编：包里的东西全部出自这次的代码，换过目录的检出也不会撞上旧的编译记录
ACTIONS=(build)
[ "$RELEASE" = "1" ] && ACTIONS=(clean build)

echo "Building Ask Free (Release, arm64 + x86_64, signing: $SIGN_IDENTITY)..."
# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO：Xcode 默认往签名里加 get-task-allow（允许别的程序挂调试器），
# 带着它，本机其他程序能借用 Ask Free 已经拿到的麦克风、屏幕录制和辅助功能权限，苹果也不给公证
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme AskFree \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS="arm64 x86_64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="$SIGN_TEAM" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    OTHER_CODE_SIGN_FLAGS="$SIGN_FLAGS" \
    ENABLE_HARDENED_RUNTIME="$HARDENED_RUNTIME" \
    -quiet \
    "${ACTIONS[@]}"

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$BUILT_APP" "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

BINARY="$APP_DIR/Contents/MacOS/AskFree"
ARCHS_BUILT="$(lipo -archs "$BINARY")"
for arch in arm64 x86_64; do
    [[ " $ARCHS_BUILT " == *" $arch "* ]] || fail "可执行文件里没有 $arch（现在是：$ARCHS_BUILT）"
done
if codesign -d --entitlements - --xml "$APP_DIR" 2>/dev/null | grep -q "get-task-allow"; then
    fail "签名里还带着调试权限 get-task-allow"
fi

if [ "$RELEASE" = "1" ]; then
    SIGN_INFO="$(codesign -dvv "$APP_DIR" 2>&1)"
    grep -q "^Authority=Developer ID Application:" <<<"$SIGN_INFO" || fail "签名的 Authority 不是 Developer ID Application"
    grep -q "^TeamIdentifier=$TEAM_ID$" <<<"$SIGN_INFO" || fail "签名的团队号不是 $TEAM_ID（$(grep '^TeamIdentifier=' <<<"$SIGN_INFO")）"
    grep -q "^Timestamp=" <<<"$SIGN_INFO" || fail "签名里没有苹果的安全时间戳（Timestamp=）"
    grep -q "runtime" <<<"$(grep '^CodeDirectory' <<<"$SIGN_INFO")" || fail "没开 hardened runtime"
    echo "   签名核对通过：Developer ID · 团队 $TEAM_ID · 带时间戳 · 无 get-task-allow · hardened runtime"
fi

echo "✅ Built $APP_DIR ($(du -sh "$APP_DIR" | cut -f1), $ARCHS_BUILT)"
echo "   Install: bash \"$ROOT_DIR/scripts/install_app.sh\""

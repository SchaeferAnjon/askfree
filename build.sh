#!/bin/bash
# 编译 Release 版 Ask Free，产物在 dist/Ask Free.app。
# 有 Developer ID 证书（local.build.env 里的 DEVELOPER_ID_IDENTITY）就用它签名，没有就 ad hoc 签名，自己用足够。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_PATH="$ROOT_DIR/AskFree.xcodeproj"
# 不放 ~/Documents 下：那里的 iCloud 扩展属性会让 codesign 失败
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/private/tmp/askfree-release-dd}"
BUILT_APP="$DERIVED_DATA_PATH/Build/Products/Release/Ask Free.app"
APP_DIR="$ROOT_DIR/dist/Ask Free.app"

if [ -f "$ROOT_DIR/local.build.env" ]; then
    # shellcheck disable=SC1091
    . "$ROOT_DIR/local.build.env"
fi
DEVELOPER_ID_IDENTITY="${DEVELOPER_ID_IDENTITY:-}"

# 改过 project.yml 又装了 xcodegen：先重新生成工程
if command -v xcodegen >/dev/null 2>&1; then
    (cd "$ROOT_DIR" && xcodegen generate --quiet)
fi

if [ -n "$DEVELOPER_ID_IDENTITY" ] && security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEVELOPER_ID_IDENTITY"; then
    SIGN_IDENTITY="$DEVELOPER_ID_IDENTITY"
else
    SIGN_IDENTITY="-"
fi
# 临时签名（ad hoc）的包不开 hardened runtime：开了的话系统的库校验要求 App 和 Sparkle.framework 是同一个团队签的，
# 临时签名没有团队号，App 一启动就因为加载不了 Sparkle 退出。Developer ID 签的包照常开
HARDENED_RUNTIME=YES
[ "$SIGN_IDENTITY" = "-" ] && HARDENED_RUNTIME=NO

echo "Building Ask Free (Release, signing: $SIGN_IDENTITY)..."
xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme AskFree \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
    ENABLE_HARDENED_RUNTIME="$HARDENED_RUNTIME" \
    -quiet \
    build

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$BUILT_APP" "$APP_DIR"
xattr -cr "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "✅ Built $APP_DIR ($(du -sh "$APP_DIR" | cut -f1))"
echo "   Install: bash \"$ROOT_DIR/scripts/install_app.sh\""

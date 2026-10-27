#!/bin/bash
# Xcode 编完、给 App 签名之前跑（project.yml 的 postBuildScripts，变量都是 Xcode 给的）：
# Sparkle 预编译包里的 Autoupdate、Updater.app 和两个 XPC 服务是临时签名的，Xcode 嵌进来时只重签外层的 Sparkle.framework。
# 这里用和 App 同一个签名身份、带 hardened runtime 把它们逐个重签，最后签 framework：
# 更新时 Sparkle 跑的辅助程序和 App 是同一个 Developer ID，苹果公证也认（Sparkle 文档「Distributing」一节的做法）。
set -euo pipefail

if [ "${CODE_SIGNING_ALLOWED:-YES}" = "NO" ]; then
    echo "不签名的编译，跳过 Sparkle 重签"
    exit 0
fi

FRAMEWORK="$TARGET_BUILD_DIR/$FRAMEWORKS_FOLDER_PATH/Sparkle.framework"
if [ ! -d "$FRAMEWORK" ]; then
    echo "error: 没找到 $FRAMEWORK：Sparkle 没嵌进 App" >&2
    exit 1
fi
IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:--}"
B="$FRAMEWORK/Versions/B"

sign() {
    # OTHER_CODE_SIGN_FLAGS 是 build.sh 传的（Developer ID 时有 --timestamp），要按空格拆开
    # shellcheck disable=SC2086
    codesign --force --sign "$IDENTITY" --options runtime ${OTHER_CODE_SIGN_FLAGS:-} "$@"
}
sign "$B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$B/XPCServices/Downloader.xpc"
sign "$B/Autoupdate"
sign "$B/Updater.app"
sign "$FRAMEWORK"
echo "Sparkle 重签完成（${EXPANDED_CODE_SIGN_IDENTITY_NAME:-$IDENTITY}）"

#!/bin/bash
# 编译并安装到 /Applications/Ask Free.app。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$ROOT_DIR/dist/Ask Free.app"
TARGET_APP="/Applications/Ask Free.app"

bash "$ROOT_DIR/build.sh"

osascript -e 'tell application "Ask Free" to quit' >/dev/null 2>&1 || true
sleep 1

# 先删再拷：直接 ditto 覆盖已安装的 App 会被 macOS「应用管理」保护拦下（Operation not permitted）
rm -rf "$TARGET_APP"
ditto "$APP_DIR" "$TARGET_APP"

echo "Installed to $TARGET_APP"
codesign -dv --verbose=2 "$TARGET_APP" 2>&1 | awk -F= '
  /^Identifier=/ { print "  Identifier: " $2 }
  /^Authority=/ && !seen[$2]++ { print "  Authority: " $2 }
'

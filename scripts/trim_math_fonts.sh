#!/bin/bash
# Xcode 编完、给 App 签名之前跑（project.yml 的 postBuildScripts，变量都是 Xcode 给的）：
# 公式排版库 SwiftMath 的资源包里带了 12 套数学字体（7.1 MB），回答里只用 Latin Modern Math（MathGlyphs 只调 latinModernFont）。
# SwiftMath 按名字用到哪套才读哪套，这里把别的字体和用不上的文件删掉，只留 latinmodern-math 的字体、数学表和两份许可证。
# 能重复跑；不签名的编译（CODE_SIGNING_ALLOWED=NO）也照常跑。删完缺了 latinmodern 那两个文件就报错，免得打出一个排不出公式的包
set -euo pipefail

RESOURCES="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
found=0
while IFS= read -r -d '' bundle; do
    found=1
    for f in "$bundle"/*; do
        name="$(basename "$f")"
        case "$name" in
            latinmodern-math.otf|latinmodern-math.plist|LICENSE|GUST-FONT-LICENSE.txt) ;;
            *) rm -rf "$f" ;;
        esac
    done
    for keep in latinmodern-math.otf latinmodern-math.plist; do
        if [ ! -f "$bundle/$keep" ]; then
            echo "error: $bundle 里没有 $keep：公式会排不出来" >&2
            exit 1
        fi
    done
    echo "公式字体只留 Latin Modern Math：$(du -sh "$bundle" | cut -f1) $bundle"
done < <(find "$RESOURCES" -type d -name mathFonts.bundle -print0)

if [ "$found" = "0" ]; then
    echo "error: $RESOURCES 下没找到 mathFonts.bundle：SwiftMath 的资源包没打进 App" >&2
    exit 1
fi

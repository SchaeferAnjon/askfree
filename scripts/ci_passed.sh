#!/bin/bash
# 发版前核对：这个 tag 指的提交上，CI（.github/workflows/build.yml：单元测试、编译、启动自测）跑完并且通过了。
# 发版脚本这样调用：bash scripts/ci_passed.sh v1.2.0 || exit 1
# 通过：退出码 0，打印那次 CI 的地址；没跑、还在跑、没过：退出码 1，说怎么看。
set -euo pipefail

REPO="SchaeferAnjon/askfree"
[ $# -eq 1 ] || { echo "用法：bash scripts/ci_passed.sh <tag>（例如 v1.2.0）" >&2; exit 2; }
TAG="$1"
fail() {
    echo "CI 没过：$1" >&2
    exit 1
}

SHA="$(git rev-parse --verify --quiet "$TAG^{commit}")" || fail "本机没有 $TAG（git fetch --tags 一下）"
# 推 tag 触发的那次 CI，headBranch 就是 tag 名；同一个提交跑过几次时取最新的一次
LINE="$(gh run list -R "$REPO" --workflow build.yml --branch "$TAG" --limit 20 \
    --json databaseId,headSha,status,conclusion \
    --jq "[.[] | select(.headSha == \"$SHA\")][0] // empty | \"\(.databaseId) \(.status) \(.conclusion)\"" 2>&1)" \
    || fail "查不了 GitHub 上的 CI：$LINE"
[ -n "$LINE" ] || fail "CI 还没在 $TAG（${SHA:0:7}）上跑过：tag 推上去后等一会儿，gh run list -R $REPO --workflow build.yml 看"
read -r RUN_ID STATUS CONCLUSION <<<"$LINE"
[ "$STATUS" = "completed" ] || fail "CI 还在跑（$STATUS）：gh run watch $RUN_ID -R $REPO"
[ "$CONCLUSION" = "success" ] || fail "这次 CI 的结果是 $CONCLUSION：gh run view $RUN_ID -R $REPO --log-failed"
echo "CI 通过：$TAG（${SHA:0:7}）https://github.com/$REPO/actions/runs/$RUN_ID"

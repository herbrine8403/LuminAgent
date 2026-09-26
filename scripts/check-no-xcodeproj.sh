#!/bin/bash
# 守卫脚本：发现任何 *.xcodeproj 即非零退出，禁止提交 Xcode 工程。
# 用法：bash scripts/check-no-xcodeproj.sh（CI 首步调用）
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
found="$(find "$ROOT" -name '*.xcodeproj' -o -name '*.xcworkspace' | head -n 20 || true)"
if [ -n "$found" ]; then
  echo "[guard] 发现禁用的 Xcode 工程文件，拒绝构建：" >&2
  echo "$found" >&2
  exit 1
fi
echo "[guard] 未发现 *.xcodeproj/*.xcworkspace，检查通过。"

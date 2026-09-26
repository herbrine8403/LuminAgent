#!/bin/bash
# 打包辅助：校验 Payload 目录结构（真正的 zip 由 Makefile METHOD_PACKAGE 执行）。
# 用法：bash scripts/package-ipa.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$ROOT/Payload" ]; then
  echo "[package] 缺少 Payload 目录，请先执行 make payload" >&2
  exit 1
fi
app_count="$(find "$ROOT/Payload" -maxdepth 2 -name '*.app' | wc -l | tr -d ' ')"
if [ "$app_count" = "0" ]; then
  echo "[package] Payload 下未找到 .app，请先执行 make payload" >&2
  exit 1
fi
echo "[package] Payload 校验通过（.app 数量：$app_count）。"

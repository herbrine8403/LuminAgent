#!/bin/bash
# 符号收集辅助：校验主可执行文件存在（真正的 dsymutil 由 Makefile 执行）。
# 用法：bash scripts/collect-dsym.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/artifacts/LuminAgent.app/LuminAgent"
if [ ! -f "$BIN" ]; then
  echo "[dsym] 未找到主可执行文件：$BIN（payload 阶段会生成），仅做存在性提示。" >&2
fi
echo "[dsym] 收集前检查完成。"

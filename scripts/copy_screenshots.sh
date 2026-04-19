#!/bin/bash
# 将 fastlane 截图拷贝到 marketing/screenshots/，并去掉设备前缀，保持文件名稳定
# (例如: "iPhone 17 Pro Max-01-home.png" -> "01-home.png")
# 若未生成任何截图则返回非 0，便于 CI 捕获。
set -euo pipefail

DEST="marketing/screenshots"
mkdir -p "$DEST"

copied=0
for lang_dir in fastlane/screenshots/zh-Hans fastlane/screenshots/en-US; do
  [ -d "$lang_dir" ] || continue
  for f in "$lang_dir"/*.png; do
    [ -f "$f" ] || continue
    base=$(basename "$f")
    stable=$(echo "$base" | sed -E 's/^.*-([0-9]{2}-)/\1/')
    cp "$f" "$DEST/$stable"
    copied=$((copied + 1))
  done
done

echo "Copied $copied screenshot(s) to $DEST/"

if [ "$copied" -eq 0 ]; then
  # 没有 fastlane 截图时，若 marketing/screenshots 已有占位图则不视为错误
  existing=$(find "$DEST" -maxdepth 1 -name '*.png' | wc -l | tr -d ' ')
  if [ "$existing" -eq 0 ]; then
    echo "WARN: marketing/screenshots/ 暂无截图，页面中的 <img> 将显示为破碎图标。" >&2
    echo "      可运行 'bundle exec fastlane snapshot' 生成，或手工放入 01-home.png 等文件。" >&2
  else
    echo "使用已存在于 $DEST 的 $existing 张截图。"
  fi
fi

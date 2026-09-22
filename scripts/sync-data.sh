#!/bin/zsh
# 把 data/ 下的权威 JSON 同步到 Windows 与 macOS 两端的内置资源目录。
#
#   zsh scripts/sync-data.sh
#
# 源文件名带版本号（data/nightreign-<名字>-v<版本>.json），目标文件名统一为
# <名字>.json —— 两端的加载代码只认目标文件名，换版本时只改本脚本的映射表。
# 源文件不存在时跳过并提示（bosses / skills / buffs / heroes 由另一条数据流水线生成，
# 若某个源文件缺失则跳过，两端会继续使用 resources/ 里已有的副本；只有当副本是占位 JSON 时页面才显示「数据未内置」）。
set -euo pipefail

ROOT="${0:A:h:h}"
WIN_RES="$ROOT/windows/resources"
MAC_RES="$ROOT/macos/Sources/NightreignRelicChecker/Resources"

# "源文件名:目标文件名"
typeset -a PAIRS
PAIRS=(
  "nightreign-affixes-v1.03.4.json:affixes.json"
  "nightreign-relics-v1.03.4.json:relics.json"
  "nightreign-bosses-v1.03.5.json:bosses.json"
  "nightreign-skills-v1.03.5.json:skills.json"
  "nightreign-buffs-v1.03.5.json:buffs.json"
  "nightreign-heroes-v1.03.5.json:heroes.json"
)

copied=0
skipped=0

for target_dir in "$WIN_RES" "$MAC_RES"; do
  if [[ ! -d "$target_dir" ]]; then
    print -r -- "错误：资源目录不存在：$target_dir" >&2
    exit 1
  fi
done

for pair in $PAIRS; do
  src_name="${pair%%:*}"
  dest_name="${pair##*:}"
  src="$ROOT/data/$src_name"

  if [[ ! -f "$src" ]]; then
    print -r -- "跳过（源文件不存在）：data/$src_name → $dest_name"
    skipped=$((skipped + 1))
    continue
  fi

  # 坏 JSON 不应污染两端的内置资源（python3 缺失时跳过该校验）。
  if command -v python3 >/dev/null 2>&1; then
    if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$src" >/dev/null 2>&1; then
      print -r -- "错误：data/$src_name 不是合法 JSON" >&2
      exit 1
    fi
  fi

  cp "$src" "$WIN_RES/$dest_name"
  cp "$src" "$MAC_RES/$dest_name"
  print -r -- "已同步：data/$src_name → windows/resources/$dest_name、macos/…/Resources/$dest_name"
  copied=$((copied + 1))
done

print -r -- "完成：同步 $copied 项，跳过 $skipped 项。"
if (( skipped > 0 )); then
  print -r -- "提示：被跳过的数据文件在 data/ 生成后重新运行本脚本即可，两端无需改代码。"
fi

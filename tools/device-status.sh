#!/usr/bin/env bash
# 一次性输出设备状态报告(纯文本,不吃多模态 token)
#
# 用法:
#   bash tools/device-status.sh                           # 默认 TV
#   bash tools/device-status.sh "$PICO_ADDR"
#   bash tools/device-status.sh "$TV_ADDR" com.example.dualdemo
#
# 输出: 型号/系统/ABI → 目标包是否安装及版本 → 当前前台 → 最近崩溃 → 当前界面文案
#
# 跨平台:Windows 原生 / WSL2 / Linux 均可,差异见 tools/_common.sh 顶部。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# 只取第一个位置参数 —— 用 source 加载本文件时 $@ 会带上外层参数,
# 那不是我们想要的。显式按需读取即可(下面用 ${1:-} 而非数组)。
DEV="${1:-$TV_ADDR}"
PKG="${2:-}"
[ -n "$ADB" ] || { echo "!! 找不到可用的 adb(见 tools/README.md)" >&2; exit 1; }

A(){ run_timeout 30 "$ADB" -s "$DEV" shell "$@" </dev/null 2>&1; }

# 收尾时把落在设备上的 dump 文件清掉。用 trap 而不是写在末尾 ——
# Ctrl-C / 中途报错退出时末尾那行不会执行,文件就留在 /sdcard 了。
trap 'A "rm -f /sdcard/_status.xml" >/dev/null 2>&1' EXIT

if ! adb_online "$DEV"; then
  echo "设备 $DEV 未连接。先跑: bash tools/devices.sh" >&2
  exit 1
fi

echo "════════ 设备 $DEV ════════"
printf '  型号     %s(device=%s)\n' \
  "$(A getprop ro.product.manufacturer)$(A getprop ro.product.model) " \
  "$(A getprop ro.product.device)"
printf '  系统     Android %s / API %s\n' \
  "$(A getprop ro.build.version.release)" "$(A getprop ro.build.version.sdk)"
printf '  ABI      %s\n' "$(A getprop ro.product.cpu.abilist)"
printf '  shell    %s\n' "$(A id | tr -d '\r')"

if [ -n "$PKG" ]; then
  echo
  echo "════════ 目标包 $PKG ════════"
  if A pm list packages | grep -q "package:$PKG"; then
    A dumpsys package "$PKG" 2>/dev/null \
      | grep -E 'versionName|primaryCpuAbi|installerPackageName|firstInstallTime|lastUpdateTime' \
      | sed 's/^ */  /'
  else
    echo "  未安装"
  fi
fi

echo
echo "════════ 当前前台 ════════"
A dumpsys activity activities | grep -m1 mResumedActivity | tr -d '\r' | sed 's/^ */  /'

echo
echo "════════ 最近崩溃(最近 300 行日志)════════"
crashes=$(A logcat -d -t 300 | grep -iE 'FATAL EXCEPTION|AndroidRuntime.*Exception' | head -8)
if [ -n "$crashes" ]; then echo "$crashes" | sed 's/^ */  /'; else echo "  无"; fi

echo
echo "════════ 当前界面文案 ════════"
UI_XML="$TMP/_status.xml"
A uiautomator dump /sdcard/_status.xml >/dev/null 2>&1
if run_timeout 30 "$ADB" -s "$DEV" pull /sdcard/_status.xml "$UI_XML" </dev/null >/dev/null 2>&1 \
   && [ -s "$UI_XML" ]; then
  if [ -n "$PY" ]; then
    "$PY" - "$(pyfile "$UI_XML")" <<'PY' | sed 's/^/  /'
import re, sys
try:
    s = open(sys.argv[1], encoding='utf-8').read()
except Exception:
    print('(读不到 UI 树)'); raise SystemExit
seen, out = set(), []
for x in re.findall(r'<node[^>]*>', s):
    t = re.search(r'text="([^"]*)"', x)
    d = re.search(r'content-desc="([^"]*)"', x)
    T = (t.group(1) if t else '') or (d.group(1) if d else '')
    if T and T not in seen:
        seen.add(T); out.append(T)
print(' | '.join(out[:40]) if out else
      '0 个带文案的节点。若是 TV,先确认不是屏保(见 AGENTS.md);若是 Pico,UI 树本就拿不到(见 docs/04)')
PY
  else
    grep -oE 'text="[^"]+"' "$UI_XML" | head -40 | sed 's/^/  /'
  fi
else
  echo "  (拉取 UI 树失败)"
fi

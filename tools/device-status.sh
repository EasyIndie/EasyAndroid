#!/usr/bin/env bash
# 一次性输出设备状态报告(纯文本,不吃多模态 token)
#
# 用法:
#   bash tools/device-status.sh                 # 默认 TV
#   bash tools/device-status.sh "$PICO_ADDR"
#   bash tools/device-status.sh "$TV_ADDR" com.example.dualdemo
#
# 输出: 型号/系统/ABI → 目标包是否安装及版本 → 当前前台 → 最近崩溃 → 当前界面文案
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DEV="${1:-$TV_ADDR}"
PKG="${2:-}"

A(){ timeout 30 adb -s "$DEV" shell "$@" </dev/null 2>&1; }

if ! adb devices | awk -v d="$DEV" '$1==d && $2=="device"' | grep -q .; then
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
A uiautomator dump /sdcard/_status.xml >/dev/null 2>&1
if timeout 30 adb -s "$DEV" pull /sdcard/_status.xml /tmp/_status.xml </dev/null >/dev/null 2>&1; then
  python3 - <<'PY' | sed 's/^/  /'
import re
try:
    s = open('/tmp/_status.xml', encoding='utf-8').read()
except Exception:
    print('(读不到 UI 树)'); raise SystemExit
seen, out = set(), []
for x in re.findall(r'<node[^>]*>', s):
    t = re.search(r'text="([^"]*)"', x)
    d = re.search(r'content-desc="([^"]*)"', x)
    T = (t.group(1) if t else '') or (d.group(1) if d else '')
    if T and T not in seen:
        seen.add(T); out.append(T)
print(' | '.join(out[:40]) if out else '0 个带文案的节点。若设备是 TV,先确认是不是在屏保(见 AGENTS.md)')
PY
else
  echo "  (拉取 UI 树失败)"
fi

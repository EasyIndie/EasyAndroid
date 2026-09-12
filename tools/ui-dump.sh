#!/usr/bin/env bash
#
# 触发应用「自截图」并把 PNG 拉回本地
#
# 适用场景
#   · Pico 4 这类 `screencap` 被 FLAG_SECURE 挡掉的设备(抓出来是纯白图)
#   · 任何想在不依赖 uiautomator 的情况下看真实渲染结果的时候
#
# 前提
#   应用里已经集成了 debug 自截图钩子。模板在
#   apps/DualDemo/app/src/debug/,把那几个文件拷进你的工程即可,
#   细节见 docs/07-debug-ui-capture.md。**只在 debug 构建里可用。**
#
# 用法
#   bash tools/ui-dump.sh <package.id>                     # 默认设备 = device.env 里的 PICO_ADDR
#   bash tools/ui-dump.sh <package.id> "$TV_ADDR"          # 指定设备
#   bash tools/ui-dump.sh <package.id> "$PICO_ADDR" /tmp/a.png
#   bash tools/ui-dump.sh <package.id> --launch            # 先拉起应用再截图
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

PKG=""; DEV=""; OUT=""; DO_LAUNCH=0
for a in "$@"; do
  case "$a" in
    --launch) DO_LAUNCH=1 ;;
    *) if [ -z "$PKG" ]; then PKG="$a"
       elif [ -z "$DEV" ]; then DEV="$a"
       else OUT="$a"; fi ;;
  esac
done

[ -n "$PKG" ] || { echo "用法: $0 <package.id> [设备serial] [输出路径] [--launch]" >&2; exit 2; }
DEV="${DEV:-$PICO_ADDR}"
OUT="${OUT:-/tmp/ui-dump-$(echo "$PKG" | tr '.' '_').png}"

A(){ timeout 40 adb -s "$DEV" shell "$@" </dev/null 2>&1; }

if ! adb devices | awk -v d="$DEV" '$1==d && $2=="device"' | grep -q .; then
  echo "设备 $DEV 未连接。先跑: bash tools/devices.sh" >&2
  exit 1
fi

REMOTE="/sdcard/Android/data/$PKG/files/ui-dump.png"

if [ "$DO_LAUNCH" = 1 ]; then
  echo "==> 拉起应用"
  A input keyevent KEYCODE_WAKEUP >/dev/null
  A monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3
fi

# 清掉旧图,这样「文件出现」就等于「本次截图成功」
A "rm -f $REMOTE" >/dev/null 2>&1

echo "==> 广播触发自截图"
A "am broadcast -a ${PKG}.DUMP_UI -p ${PKG}" 2>&1 | grep -E 'Broadcast|Error' | sed 's/^ */  /'

# 等 PNG 落地
ok=0
for _ in $(seq 1 20); do
  if A "test -s $REMOTE && echo yes" | grep -q yes; then ok=1; break; fi
  sleep 0.5
done

if [ "$ok" != 1 ]; then
  echo "!! 没等到截图文件。可能原因:" >&2
  echo "   · 应用不在前台(View 已停止重绘)" >&2
  echo "   · 工程里没集成 debug 自截图钩子(见 docs/07)" >&2
  echo "   · 装的是 release 包(钩子只在 debug 构建里)" >&2
  A "logcat -d -t 60" 2>/dev/null | grep -iE 'UiDump|AndroidRuntime' | tail -6 >&2
  exit 1
fi

rm -f "$OUT"
timeout 60 adb -s "$DEV" pull "$REMOTE" "$OUT" </dev/null >/dev/null 2>&1 || {
  echo "!! 拉取失败: $REMOTE" >&2; exit 1; }

python3 - "$OUT" <<'PYEOF'
import struct, sys, os
p = sys.argv[1]
d = open(p, 'rb').read()
if d[:8] != b'\x89PNG\r\n\x1a\n':
    print(f'  {p} ({len(d)} bytes) —— 不是 PNG?'); raise SystemExit
w, h = struct.unpack('>II', d[16:24])
print(f'  {p}')
print(f'  {w}x{h}, {len(d)} bytes')
PYEOF

echo
echo "看这张图可以直接交给支持视觉的模型判断 UI 渲染是否正确。"

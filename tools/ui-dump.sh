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
#   bash tools/ui-dump.sh <package.id> "$PICO_ADDR" out.png
#   bash tools/ui-dump.sh <package.id> --launch            # 先拉起应用再截图
#
# 跨平台:Windows 原生 / WSL2 / Linux 均可,差异见 tools/_common.sh 顶部。
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
[ -n "$ADB" ]   || { echo "!! 找不到可用的 adb(见 tools/README.md)" >&2; exit 1; }

DEV="${DEV:-$PICO_ADDR}"
OUT="${OUT:-$TMP/ui-dump-$(printf '%s' "$PKG" | tr '.' '_').png}"

A(){ run_timeout 40 "$ADB" -s "$DEV" shell "$@" </dev/null 2>&1; }

if ! adb_online "$DEV"; then
  echo "设备 $DEV 未连接。先跑: bash tools/devices.sh" >&2
  exit 1
fi

EXT_PNG="/sdcard/Android/data/$PKG/files/ui-dump.png"
INT_REL="files/ui-dump.png"          # 相对应用私有目录,用 run-as 取

if [ "$DO_LAUNCH" = 1 ]; then
  echo "==> 拉起应用"
  A input keyevent KEYCODE_WAKEUP >/dev/null
  A monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
  sleep 3
fi

# 清掉旧图与旧错误标记,这样「新文件出现」就等于「本次截图成功」
A "rm -f $EXT_PNG" >/dev/null 2>&1
A "run-as $PKG rm -f $INT_REL files/ui-dump.error" >/dev/null 2>&1

echo "==> 广播触发自截图"
A "am broadcast -a ${PKG}.DUMP_UI -p ${PKG}" 2>&1 | grep -E 'Broadcast|Error' | sed 's/^ */  /'

# 等 PNG 落地。注意 Android 11+ 上 shell 读不了 /sdcard/Android/data/*,
# 所以这里用两条判断:外部目录(旧系统)和 run-as 内部目录(新系统)。
newer_exists(){
  A "test -s $EXT_PNG && echo yes" 2>/dev/null | grep -q yes && return 0
  A "run-as $PKG test -s $INT_REL && echo yes" 2>/dev/null | grep -q yes && return 0
  return 1
}

ok=0
for _ in $(seq 1 20); do
  newer_exists && { ok=1; break; }
  sleep 0.5
done

if [ "$ok" != 1 ]; then
  echo "!! 没等到截图文件。原因:" >&2
  err="$(A "run-as $PKG cat files/ui-dump.error 2>/dev/null" | head -3)"
  if [ -n "$err" ]; then
    echo "   应用报了: $err" >&2
  else
    echo "   · 广播没到接收器 —— 工程里没集成钩子?装的是 release 包?" >&2
    echo "   · 应用不在前台(View 已停止重绘)" >&2
    echo "     Pico 上还可能是头显睡了,先跑 tools/pico-panel.sh <pkg> awake" >&2
    echo "   详解见 docs/07-debug-ui-capture.md" >&2
  fi
  A "logcat -d -t 80" 2>/dev/null | grep -iE 'UiDump|AndroidRuntime' | tail -6 >&2
  exit 1
fi

rm -f "$OUT"
# 先试外部目录(Android 10 及更早可以直接 pull)
# pull 目标过 win_of:adb.exe 不认 Git Bash 的 /e/... 形式;下面的 > "$OUT"
# 重定向由 bash 处理,保持 POSIX 形式即可,两者不能混
if ! run_timeout 60 "$ADB" -s "$DEV" pull "$EXT_PNG" "$(win_of "$OUT")" </dev/null >/dev/null 2>&1; then
  # Android 11+ 只能用 run-as 把内部那份流出来
  if ! run_timeout 60 "$ADB" -s "$DEV" exec-out run-as "$PKG" cat "$INT_REL" \
       > "$OUT" 2>/dev/null; then
    echo "!! 取图失败" >&2; exit 1
  fi
fi

[ -s "$OUT" ] || { echo "!! 取到的文件是空的" >&2; exit 1; }

if [ -n "$PY" ]; then
  # 传 Windows 形式路径:Windows 原生 python 不认 Git Bash 的 /e/... 形式
  "$PY" - "$(pyfile "$OUT")" <<'PYEOF'
import struct, sys
p = sys.argv[1]
d = open(p, 'rb').read()
if d[:8] != b'\x89PNG\r\n\x1a\n':
    print(f'  {p} ({len(d)} bytes) —— 不是 PNG?'); raise SystemExit
w, h = struct.unpack('>II', d[16:24])
print(f'  {w}x{h}, {len(d)} bytes')
PYEOF
else
  printf '  %s bytes(没找到 python3,跳过尺寸解析)\n' "$(file_size "$OUT")"
fi

echo "  $OUT"

echo
echo "看这张图可以直接交给支持视觉的模型判断 UI 渲染是否正确。"

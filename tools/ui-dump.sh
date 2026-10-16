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

# 目标设备是不是 Pico —— 用于只在 Pico 上才有意义的提示。
# 只在失败路径上调,多一次 adb 调用可以接受。
is_pico(){
  case "$(A getprop ro.product.manufacturer)$(A getprop ro.product.model)" in
    *Pico*|*PICO*|*pico*) return 0 ;;
    *) return 1 ;;
  esac
}

# 装的包是不是 debuggable —— 决定 run-as / 自截图钩子能不能用。
# 只在失败路径上调,多一次 adb 调用可以接受。
is_debuggable(){ A "dumpsys package $PKG" 2>/dev/null | grep -q 'DEBUGGABLE'; }
pkg_installed(){ A "pm list packages" 2>/dev/null | grep -q "package:$PKG"; }

# 从 applicationId 反查工程目录,好给出**可直接复制**的 debug 包路径。
# 拿不到就返回非零,调用方退回写 <repo>/apps/<Name>/... 的占位说法。
app_dir_for(){
  local pkg="$1" f
  f="$(grep -rl "applicationId = \"$pkg\"" "$_REPO_DIR/apps" --include='build.gradle.kts' 2>/dev/null | head -1)"
  [ -n "$f" ] || return 1
  # <apps>/<Name>/app/build.gradle.kts -> <apps>/<Name>
  dirname "$(dirname "$f")"
}

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
  elif ! pkg_installed; then
    echo "   · $PKG 没装在这台设备上" >&2
  elif ! is_debuggable; then
    # 最常见也最容易被误判的一种:设备上装的是正式包。
    # 自截图钩子在 src/debug/,正式包里压根没有 —— 而且 run-as 也用不了
    # (它只对 debuggable 应用有效)。直接说透,省得去查“是不是没集成钩子”。
    echo "   · **设备上装的是正式包**(非 debuggable),而自截图钩子只在 debug 包里" >&2
    echo "     验收请装 debug 包 —— 开发/验收全程用 debug,只有发版才出正式包。" >&2
    adbg="$(app_dir_for "$PKG" 2>/dev/null)"
    if [ -n "$adbg" ] && [ -f "$adbg/app/build/outputs/apk/debug/app-debug.apk" ]; then
      echo "       \"$ADB\" -s $DEV uninstall $PKG" >&2
      echo "       \"$ADB\" -s $DEV install -r $adbg/app/build/outputs/apk/debug/app-debug.apk" >&2
    else
      echo "       \"$ADB\" -s $DEV uninstall $PKG" >&2
      echo "       \"$ADB\" -s $DEV install -r apps/<Name>/app/build/outputs/apk/debug/app-debug.apk" >&2
    fi
    echo "     (签名不同,换装前必须先 uninstall;见 docs/06「构建与发布」)" >&2
  else
    echo "   · 广播没到接收器 —— 工程里没集成钩子?" >&2
    echo "   · 应用不在前台(View 已停止重绘)" >&2
    # 头显睡了是 Pico 特有的坑,别在电视上乱提示把真原因淹没
    # (实测在电视上看到「Pico 上还可能是头显睡了」会直接让人懵)
    if is_pico; then
      echo "   · 头显睡了 —— 先跑 tools/pico-panel.sh <pkg> awake" >&2
    fi
    echo "   详解见 docs/07-debug-ui-capture.md" >&2
  fi
  A "logcat -d -t 80" 2>/dev/null | grep -iE 'UiDump|AndroidRuntime' | tail -6 >&2
  exit 1
fi

rm -f "$OUT"

# 两条取图路径:
#   pull  —— 外部目录(Android 10 及更早,shell 可以直接读)
#   run-as —— 把应用私有目录那份流出来(Android 11+ /sdcard/Android/data
#             对 shell 不可读)
# pull 目标过 win_of:adb.exe 不认 Git Bash 的 /e/... 形式;run-as 的
# 重定向由 bash 处理,保持 POSIX 形式即可,两者不能混。
fetch_pull()  { run_timeout 60 "$ADB" -s "$DEV" pull "$EXT_PNG" "$(win_of "$OUT")" </dev/null >/dev/null 2>&1; }
fetch_runas() { run_timeout 60 "$ADB" -s "$DEV" exec-out run-as "$PKG" cat "$INT_REL" > "$OUT" 2>/dev/null; }

# ⚠️ 判据是**本地文件非空**,不是退出码。
#    踩过:`adb pull` 在 Android 11+ 上会失败得"半途而废" —— 本地文件已经建好,
#    内容是 0 字节,而脚本只看退出码就往下走了,最后报一句
#    「取到的文件是空的」,看着像钩子坏了(设备端明明有图,上面 newer_exists
#    已经用 `test -s` 验过非空)。现在:一条路拿到空文件就换另一条再试一次。
fetch_pull  || true
[ -s "$OUT" ] || { rm -f "$OUT"; fetch_runas || true; }

# 还是空 → 很可能撞上了「应用刚被拉起、首帧还没画完」。
# 实测:verify-all 刚拉起应用后紧接着调本脚本,设备端写出的是 0 字节图;
# 隔几秒重跑就正常,而且此后一直正常(瞬态,不是钩子坏了)。
# 与其让调用方去猜,这里直接重播一次广播再等一会儿。
if [ ! -s "$OUT" ]; then
  echo "   首次取到空图,重播一次广播…" >&2
  A "am broadcast -a ${PKG}.DUMP_UI -p ${PKG}" >/dev/null 2>&1
  sleep 2
  rm -f "$OUT"
  fetch_pull  || true
  [ -s "$OUT" ] || { rm -f "$OUT"; fetch_runas || true; }
fi

if [ ! -s "$OUT" ]; then
  echo "!! 取图失败:本地拿到的是空文件" >&2
  devsz="$(A "run-as $PKG stat -c %s $INT_REL" 2>/dev/null | tr -d '\r' | head -1)"
  if [ -n "$devsz" ] && [ "$devsz" -gt 0 ] 2>/dev/null; then
    echo "   设备上那份其实是好的($devsz 字节),坏在**取回来**这一步" >&2
    echo "   重跑一次通常就好(已知瞬态);仍不行就手动取:" >&2
    echo "       \"$ADB\" -s $DEV exec-out run-as $PKG cat $INT_REL > /tmp/ui.png" >&2
  elif [ -n "$devsz" ]; then
    echo "   设备上那份也是空的(0 字节)—— 应用没画出画面" >&2
    echo "   · 应用不在前台(View 已停止重绘)?加上 --launch 试" >&2
    [ "$(is_pico && echo y)" = y ] && \
      echo "   · 头显睡了 —— 先跑 tools/pico-panel.sh <pkg> awake" >&2
  else
    echo "   设备上读不到那份图 —— 应用可能刚崩了" >&2
  fi
  A "logcat -d -t 80" 2>/dev/null | grep -iE 'UiDump|AndroidRuntime' | tail -6 >&2
  echo "   详解见 docs/07-debug-ui-capture.md" >&2
  exit 1
fi

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

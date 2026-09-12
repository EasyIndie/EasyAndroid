#!/usr/bin/env bash
#
# 把 APK 装到 TCL 电视上,并(默认)启动它
#
# ── 为什么不能用 adb install ──────────────────────────────────────────
# TCL 在 system_server 里打了补丁(OverseasAppConfig),凡是带 INSTALL_FROM_ADB
# 的安装一律被拒。以下全部试过,全部无效:
#   · adb install / pm install / install-create --skip-verification
#   · appops set com.android.shell REQUEST_INSTALL_PACKAGES allow
#   · settings put global verifier_verify_adb_installs 0 / package_verifier_enable 0
#   · 用 content:// URI 拉起系统安装器(InstallStart 只认 content,不接受 file)
#   · 卸载后安装、重启后安装、--no-streaming、-i 伪造商店身份
# 唯一可用通道是 TGuard 的图形化安装器(installer 记成 com.android.packageinstaller)。
# 完整排查见 docs/03-tcl-tv-sideload.md
#
# ── 性能 ────────────────────────────────────────────────────────────
# 实测几个关键开销,脚本已据此优化:
#   input keyevent   每次 ~0.9s(input 是 Java 程序,启动一次)  → 批量合并成一次调用
#   uiautomator dump 每次 ~2.5s                                → 尽量少用,能省则省
#   dumpsys          每次 ~0.12s                               → 用它代替 dump
# 目标 60~70 秒。想更快只能换设备:Pico 接受普通 adb install,2~3 秒。
#
# 用法
#   bash tools/tv-install.sh <apk>                # 安装 + 启动 + 自截图
#   bash tools/tv-install.sh <apk> --no-launch    # 只安装
#   bash tools/tv-install.sh <apk> --no-shot      # 装完不截图
#   bash tools/tv-install.sh <apk> --shot-out /tmp/x.png
#   LABEL=MyApp bash tools/tv-install.sh <apk>
#
# 装完会调用 tools/ui-dump.sh 截一张真实渲染的图(需要 debug 构建里的钩子,
# 见 docs/07-debug-ui-capture.md)。没有钩子时只提示,不影响安装结果。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

LAUNCH=1; SHOT=1; SHOT_OUT=""; ARGS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --no-launch) LAUNCH=0 ;;
    --no-shot)   SHOT=0 ;;
    --shot-out)  shift; SHOT_OUT="${1:-}" ;;
    *) ARGS+=("$1") ;;
  esac
  shift
done
APK="${ARGS[0]:-}"
[ -n "$APK" ] || { echo "用法: $0 <apk路径> [--no-launch]" >&2; exit 2; }
[ -f "$APK" ] || { echo "找不到 APK: $APK" >&2; exit 2; }

for bt in "$ANDROID_HOME"/build-tools/*/; do
  [ -x "$bt/aapt2" ] && export PATH="$bt:$PATH" && break
done
TV="${TV:-$TV_ADDR}"

A(){ timeout 40 adb -s "$TV" shell "$@" </dev/null 2>&1; }
# ⚠️ `input` 是 Java 程序,每次启动 ~0.9 秒。单发 13 个键要 11.7 秒,
# 合成一次调用只要 ~1 秒,所以统一走 keys()(空格分隔的一串 keycode)。
keys(){ A input keyevent $1 >/dev/null; sleep "${2:-0.3}"; }
key_rep(){ local k="$1" n="$2" d="${3:-0.3}" i args=""
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  for ((i=0;i<n;i++)); do args+="$k "; done
  keys "$args" "$d"; }

# ---- APK 元信息 ----
badging(){ aapt2 dump badging "$APK" 2>/dev/null; }
LABEL="${LABEL:-$(badging | sed -n "s/^application-label:'\(.*\)'/\1/p" | head -1)}"
LABEL="${LABEL:-双端演示}"
PKG="$(badging | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
VER="$(badging | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" | head -1)"
ACTIVITY="$(badging | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)"

# ---- UI 读取 ----
dumpui(){
  A uiautomator dump /sdcard/_ui.xml >/dev/null 2>&1
  timeout 30 adb -s "$TV" pull /sdcard/_ui.xml /tmp/_ui.xml </dev/null >/dev/null 2>&1
}
# 一次 dump 同时拿到「焦点项的标签」和「详情面板里的版本号」
focus_info(){
  dumpui
  python3 - <<'PYEOF'
import re
try: s = open('/tmp/_ui.xml', encoding='utf-8').read()
except Exception: print('|'); raise SystemExit
fx = None; nodes = []
for x in re.findall(r'<node[^>]*>', s):
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', x)
    if not b: continue
    bb = tuple(map(int, b.groups()))
    t = re.search(r'text="([^"]*)"', x)
    if re.search(r'focused="true"', x): fx = bb
    if t and t.group(1): nodes.append((t.group(1), bb))
label = ''
if fx:
    x1, y1, x2, y2 = fx; cands = []
    for txt, (a1, b1, a2, b2) in nodes:
        if a1 >= x1 and a2 <= x2 and b1 >= y1 and b2 <= y2:
            t = txt.strip()
            if not t or re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', t) or t == '本机已安装': continue
            cands.append(t)
    label = cands[0] if cands else ''
texts = [t.strip() for t, _ in nodes]
ver = ''
for i, t in enumerate(texts):
    if t in ('版本号', '版本') and i + 1 < len(texts): ver = texts[i + 1]; break
print(f'{label}|{ver}')
PYEOF
}
ui_text(){
  dumpui
  python3 -c "
import re
try: s=open('/tmp/_ui.xml',encoding='utf-8').read()
except Exception: raise SystemExit
seen=[]
for x in re.findall(r'<node[^>]*>',s):
    t=re.search(r'text=\"([^\"]*)\"',x)
    if t and t.group(1) and t.group(1) not in seen: seen.append(t.group(1))
print(' / '.join(seen))
"
}

# 界面状态用 dumpsys 判断(0.12s),不花 dump
foreground(){ A dumpsys window 2>/dev/null | grep -m1 mCurrentFocus | tr -d '\r' | sed 's/.*u0 //'; }
installed_version(){ [ -n "$PKG" ] && A dumpsys package "$PKG" 2>/dev/null | sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r'; }

# ---- 把 APK 推到 U 盘 ----
# 安装器的存储源叫 "SDCARD",但它扫的是【可移动存储】=U 盘,不是 /sdcard。
# 缓存以文件路径为键,文件名要唯一(包名+版本+构建时间)。
push_apk(){
  local VOL; VOL="$(A ls /storage | tr -d '\r' | grep -vxE 'emulated|self' | head -1)"
  if [ -z "$VOL" ]; then
    echo "!! 电视上没有可移动存储。TCL 的安装器只扫 U 盘,请插一个 U 盘。" >&2; exit 1
  fi
  APK_DIR="/storage/$VOL/AndroidTV"
  A "mkdir -p $APK_DIR" >/dev/null 2>&1
  local stamp; stamp="$(stat -c %Y "$APK" 2>/dev/null || date +%s)"
  local name="${PKG:-app}-${VER:-0}-${stamp}.apk"
  A "rm -f $APK_DIR/${PKG:-app}-*.apk" >/dev/null 2>&1 || true
  echo "==> 推送 APK 到 $APK_DIR/$name"
  adb -s "$TV" push "$APK" "$APK_DIR/$name" </dev/null 2>&1 | tail -1
}

# ---- 界面状态复位 ----
# 屏保会吞掉 am start;上一次的「应用安装已完成」弹窗会把后续按键全带偏。
# BACK 是幂等的,直接按两次比 dump 一次判断更便宜。
reset_ui_state(){
  keys "KEYCODE_WAKEUP KEYCODE_BACK KEYCODE_BACK KEYCODE_HOME" 1.2
  case "$(foreground)" in *Dream*) keys "KEYCODE_WAKEUP" 0.8 ;; esac
}

# ---- 打开「应用安装」页 ----
open_install_page(){
  reset_ui_state
  A am start -S -n com.tcl.guard/.appmanager.activity.AppManagerActivity >/dev/null
  sleep 2
  # 左侧栏: 应用管理 / 应用卸载 / 应用安装(UP 到顶会截断)
  keys "KEYCODE_DPAD_LEFT KEYCODE_DPAD_UP KEYCODE_DPAD_UP KEYCODE_DPAD_DOWN KEYCODE_DPAD_DOWN KEYCODE_DPAD_CENTER" 1.2
  # 进入存储源;焦点一进去就落在列表第一项
  keys "KEYCODE_DPAD_RIGHT KEYCODE_DPAD_CENTER" 1.2
  sleep 4              # 等扫描
}

# ---- 在列表里定位目标 ----
# 列表顺序稳定,会记住上次的序号(放 tools/.tv-pos-<pkg>,不入库),
# 下次直接一次批量按到那个位置,省掉十几轮 dump(每轮 2.5 秒)。
POS_FILE="$_TOOLS_DIR/.tv-pos-${PKG:-app}"
match_here(){
  local info label ver
  info="$(focus_info)"
  label="${info%%|*}"; ver="${info##*|}"
  [ "$label" = "$LABEL" ] || return 1
  if [ -n "$VER" ] && [ "$ver" != "$VER" ]; then
    echo "   跳过同名旧版本 (v${ver:-?})"; return 1
  fi
  echo "   焦点已落在「$label」 v$ver"
  keys "KEYCODE_DPAD_CENTER" 0.4
  return 0
}
locate_and_trigger(){
  local i pos
  keys "KEYCODE_DPAD_UP KEYCODE_DPAD_UP" 0.3     # 回到列表顶部
  if [ -f "$POS_FILE" ]; then
    pos="$(cat "$POS_FILE" 2>/dev/null)"
    if [ -n "$pos" ] && [ "$pos" -gt 1 ] 2>/dev/null; then
      key_rep KEYCODE_DPAD_DOWN "$((pos - 1))" 0.35
      if match_here; then return 0; fi
      echo "   位置缓存失效,从头扫"
      key_rep KEYCODE_DPAD_UP "$pos" 0.35
    fi
  fi
  for i in $(seq 1 22); do
    if match_here; then echo "$i" > "$POS_FILE" 2>/dev/null || true; return 0; fi
    keys "KEYCODE_DPAD_DOWN" 0.3
  done
  return 1
}

# ---- 盲过两道确认框 ----
# 两个对话框的默认焦点都在「取消」,RIGHT 移到确认位再按 OK。
# 不 dump 判断(每次 2.5s),装完用 versionName 校验兜底。
pass_dialogs(){
  sleep 1.8
  keys "KEYCODE_DPAD_RIGHT KEYCODE_DPAD_CENTER" 2.5
  keys "KEYCODE_DPAD_RIGHT KEYCODE_DPAD_CENTER" 3.5
  keys "KEYCODE_BACK" 0.5          # 关掉「应用安装已完成,是否立即体验?」
}

# ================= 主流程 =================
START=$(date +%s)
echo "==> 目标: ${LABEL}  (${PKG:-未知包名} v${VER:-?})  @ $TV"
push_apk

# 文件名每次构建都不同 => TGuard 缓存里必然没有 => 先重建缓存,
# 否则第一轮定位会白扫 20 多项(每项 2.5 秒)
echo "==> 重建 TGuard 扫描缓存"
A "pm clear com.tcl.guard" >/dev/null 2>&1
sleep 1.5

echo "==> 打开 安全卫士 / 应用管理器"
open_install_page

echo "==> 在列表里定位「$LABEL」"
attempt_once(){
  locate_and_trigger || return 1
  pass_dialogs
  sleep 0.8
  if [ -n "$VER" ]; then
    local v; v="$(installed_version)"
    [ "$v" = "$VER" ] || { echo "   装到的是 v${v:-?},不是目标 v$VER"; return 2; }
  fi
  return 0
}

attempt_once; rc=$?
if [ $rc -ne 0 ]; then
  echo "   重来一次(重建缓存后位置会变)"
  rm -f "$POS_FILE"
  A "pm clear com.tcl.guard" >/dev/null 2>&1
  sleep 1.5
  open_install_page
  if ! attempt_once; then
    echo "!! 安装失败" >&2
    echo "   当前焦点: $(focus_info)" >&2
    echo "   当前界面: $(ui_text | cut -c1-220)" >&2
    exit 1
  fi
fi

echo
echo "==> 结果 (耗时 $(( $(date +%s) - START ))s)"
A dumpsys package "$PKG" 2>/dev/null \
  | grep -E 'versionName|primaryCpuAbi|installerPackageName|lastUpdateTime' | sed 's/^ */  /'

if [ "$LAUNCH" = 1 ] && [ -n "$PKG" ] && [ -n "$ACTIVITY" ]; then
  echo
  echo "==> 启动"
  A input keyevent KEYCODE_WAKEUP >/dev/null
  A am start -W -n "$PKG/$ACTIVITY" 2>&1 | grep -E 'Status|Error' | sed 's/^ */  /'
  sleep 2
  echo "  前台: $(foreground)"

  # 装完自动截一张真实渲染的图 —— 一次命令就同时拿到「装好了」和「长这样」。
  # 复用 ui-dump.sh(单一实现),失败不影响安装结果:
  # release 包里没有 debug 钩子,那是预期行为。
  if [ "$SHOT" = 1 ]; then
    echo
    echo "==> 自截图"
    : "${SHOT_OUT:=/tmp/ui-dump-$(printf '%s' "$PKG" | tr '.' '_').png}"
    if ! bash "$_TOOLS_DIR/ui-dump.sh" "$PKG" "$TV" "$SHOT_OUT" 2>/tmp/_tvinstall_shot.err; then
      echo "  (跳过 —— 多半是 release 包,没有 debug 自截图钩子;见 docs/07)" >&2
      sed 's/^/    /' /tmp/_tvinstall_shot.err | head -6 >&2
    fi
  fi
fi

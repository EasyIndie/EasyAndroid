#!/usr/bin/env bash
#
# 把 APK 装到 TCL 电视上
#
# 为什么需要这个脚本
#   TCL 在当前固件的 system_server 里打了补丁(OverseasAppConfig),导致
#   adb install / pm install / install-create --skip-verification 全部返回
#   INSTALL_FAILED_VERIFICATION_FAILURE,关掉 AOSP 的 verifier 开关也没用。
#
#   唯一可用通道是 TGuard 的图形化安装器:
#     安全卫士 → 应用管理 → 应用安装 → 选 APK → 系统安装器确认
#   走这条路 installer 会记成 com.android.packageinstaller,是 TCL 认可的。
#
# 两个必须知道的机制(踩过才知道)
#   1. 安装器里的存储源叫 "SDCARD",但它扫的是【可移动存储】= 插着的 U 盘,
#      不是 /sdcard(内建存储)。所以要推到 <U盘>/AndroidTV/。
#   2. TGuard 会把扫描结果缓存下来,只在【U 盘重新挂载】或【重启】时才重建。
#      实测 pm clear com.tcl.guard 也能触发重建,比重启快得多。
#      另外缓存以【文件路径】为键,所以文件名要唯一(带包名+版本)。
#
# 用法
#   bash tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk
#   LABEL=MyApp TV=192.0.2.11:5555 bash tools/tv-install.sh <apk>
#
# 全程只用 adb + uiautomator 读界面文本,不用视觉模型。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# aapt2 用来从 APK 里读 label / package / version
for bt in "$ANDROID_HOME"/build-tools/*/; do
  [ -x "$bt/aapt2" ] && export PATH="$bt:$PATH" && break
done

TV="${TV:-$TV_ADDR}"
APK="${1:-}"
[ -n "$APK" ] || { echo "用法: $0 <apk路径>" >&2; exit 2; }
[ -f "$APK" ] || { echo "找不到 APK: $APK" >&2; exit 2; }
command -v aapt2 >/dev/null || echo "警告: 没找到 aapt2,标签匹配可能不准" >&2

A(){ timeout 40 adb -s "$TV" shell "$@" </dev/null 2>&1; }
key(){ A input keyevent "$1" >/dev/null; sleep "${2:-1}"; }

# ---- 读 APK 元信息 ----
badging(){ aapt2 dump badging "$APK" 2>/dev/null; }
LABEL="${LABEL:-$(badging | sed -n "s/^application-label:'\(.*\)'/\1/p" | head -1)}"
LABEL="${LABEL:-双端演示}"
PKG="$(badging | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
VER="$(badging | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" | head -1)"

# ---- UI 读取 ----
dumpui(){
  A uiautomator dump /sdcard/_ui.xml >/dev/null 2>&1
  timeout 30 adb -s "$TV" pull /sdcard/_ui.xml /tmp/_ui.xml </dev/null >/dev/null 2>&1
}

ui_text(){
  dumpui
  python3 - <<'PY'
import re
try: s = open('/tmp/_ui.xml', encoding='utf-8').read()
except Exception: raise SystemExit
seen = []
for x in re.findall(r'<node[^>]*>', s):
    t = re.search(r'text="([^"]*)"', x)
    if t and t.group(1) and t.group(1) not in seen:
        seen.append(t.group(1))
print(' / '.join(seen))
PY
}

# 取「bounds 落在 focused 节点内部」的文本,排除日期/状态标记
focused_label(){
  dumpui
  python3 - <<'PY'
import re
try: s = open('/tmp/_ui.xml', encoding='utf-8').read()
except Exception: print(''); raise SystemExit
fx = None; labels = []
for x in re.findall(r'<node[^>]*>', s):
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', x)
    if not b: continue
    bb = tuple(map(int, b.groups()))
    if re.search(r'focused="true"', x): fx = bb
    t = re.search(r'text="([^"]*)"', x)
    if t and t.group(1): labels.append((t.group(1), bb))
if not fx: print(''); raise SystemExit
x1, y1, x2, y2 = fx; cands = []
for txt, (a1, b1, a2, b2) in labels:
    if a1 >= x1 and a2 <= x2 and b1 >= y1 and b2 <= y2:
        t = txt.strip()
        if not t or re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', t) or t == '本机已安装': continue
        cands.append(t)
print(cands[0] if cands else '')
PY
}

wait_text(){ local pat="$1" t="${2:-20}" i
  for ((i=0;i<t;i++)); do ui_text | grep -qE "$pat" && return 0; sleep 1; done
  return 1; }

# 详情面板里「版本号」后面那个文本(用来区分同名但版本不同的条目)
detail_version(){
  dumpui
  python3 - <<'PY'
import re
try: s = open('/tmp/_ui.xml', encoding='utf-8').read()
except Exception: print(''); raise SystemExit
texts = []
for x in re.findall(r'<node[^>]*>', s):
    t = re.search(r'text="([^"]*)"', x)
    if t and t.group(1): texts.append(t.group(1))
for i, t in enumerate(texts):
    if t.strip() in ('版本号', '版本') and i + 1 < len(texts):
        print(texts[i + 1].strip()); raise SystemExit
print('')
PY
}

# ---- 推送 APK 到 U 盘 ----
push_apk(){
  VOL="$(A ls /storage | tr -d '\r' | grep -vxE 'emulated|self' | head -1)"
  if [ -z "$VOL" ]; then
    echo "!! 电视上没找到可移动存储。TCL 的安装器只扫 U 盘,请插一个 U 盘。" >&2
    exit 1
  fi
  APK_DIR="/storage/$VOL/AndroidTV"
  A "mkdir -p $APK_DIR" >/dev/null 2>&1

  # 文件名唯一且带版本:缓存以路径为键,复用同名文件会显示旧包信息
  local name="${PKG:-app}-${VER:-0}.apk"
  A "rm -f $APK_DIR/${PKG:-app}-*.apk" >/dev/null 2>&1 || true
  echo "==> 推送 APK 到 $APK_DIR/$name"
  adb -s "$TV" push "$APK" "$APK_DIR/$name" </dev/null 2>&1 | tail -1
  A "am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE -d file://$APK_DIR/$name" >/dev/null 2>&1 || true
}

# ---- 打开「应用安装」页 ----
# 先做状态清理: 屏保会吞掉 am start,残留弹窗会让后续按键全跑偏
reset_ui_state(){
  A input keyevent KEYCODE_WAKEUP >/dev/null; sleep 1
  A input keyevent KEYCODE_HOME >/dev/null; sleep 3
  # 还在屏保就再唤一次
  if A dumpsys activity activities | grep -q DreamActivity; then
    A input keyevent KEYCODE_WAKEUP >/dev/null; sleep 2
  fi
  # 清残留弹窗(上一次安装的「应用安装已完成」、错误提示框等)
  local i
  for i in 1 2 3; do
    ui_text | grep -qE '立即体验|暂不体验|知道了|是否继续安装|要安装此应用吗' || break
    A input keyevent KEYCODE_BACK >/dev/null; sleep 2
  done
}

open_install_page(){
  reset_ui_state
  A am start -S -n com.tcl.guard/.appmanager.activity.AppManagerActivity >/dev/null
  sleep 6
  ui_text | grep -qE '应用管理|应用卸载|应用安装' || {
    echo "   !! 应用管理器没打开" >&2; return 1; }

  # 左侧栏: 应用管理 / 应用卸载 / 应用安装。UP 到顶会截断,所以先归顶再下移两位
  key KEYCODE_DPAD_LEFT 2
  for i in 1 2 3 4 5; do key KEYCODE_DPAD_UP 1; done
  key KEYCODE_DPAD_DOWN 1
  key KEYCODE_DPAD_DOWN 1
  key KEYCODE_DPAD_CENTER 4

  wait_text 'SDCARD|已完成扫描|确认键安装应用' 15 || {
    echo "   !! 没进到「应用安装」页" >&2; return 1; }

  key KEYCODE_DPAD_RIGHT 2       # 进入存储源
  key KEYCODE_DPAD_CENTER 8
  wait_text '确认键安装应用|已完成扫描' 30 || true
  sleep 3
  return 0
}

# ---- 在列表里定位目标并安装 ----
# 返回 0 = 成功, 1 = 列表里没有目标
install_from_list(){
  local cur="" dv="" found=0
  for i in $(seq 1 20); do key KEYCODE_DPAD_UP 1; done    # 归顶
  for i in $(seq 1 40); do
    cur="$(focused_label)"
    if [ "$cur" = "$LABEL" ]; then
      dv="$(detail_version)"
      # 列表里可能同时存在多个同名条目(U 盘上残留的旧副本),
      # 必须按版本号挑出正确的那一个
      if [ -z "$VER" ] || [ "$dv" = "$VER" ]; then found=1; break; fi
      echo "   跳过同名但版本不符的条目 (v${dv:-?})"
    fi
    key KEYCODE_DPAD_DOWN 1
  done
  [ "$found" = 1 ] || return 1
  echo "   焦点已落在「$LABEL」 v$VER"

  key KEYCODE_DPAD_CENTER 6
  # 两道确认框: ①「应用未被认证,是否继续安装?」 ②「要安装此应用吗?」
  local r
  for r in 1 2; do
    if wait_text '是否继续安装|要安装此应用吗|是否安装' 20; then
      key KEYCODE_DPAD_RIGHT 2
      key KEYCODE_DPAD_CENTER 8
    fi
  done
  wait_text '安装完成|立即体验|应用安装已完成' 25 || true
  # 收尾: 关掉「应用安装已完成,是否立即体验?」弹窗,
  # 否则它会留在屏幕上把下一次的导航全带偏
  if wait_text '立即体验|暂不体验' 6; then
    A input keyevent KEYCODE_BACK >/dev/null; sleep 2
  fi
  return 0
}

# ---- 已安装版本(用于校验,防止匹配到缓存里的陈旧条目)----
installed_version(){
  [ -n "$PKG" ] || { printf ''; return; }
  A dumpsys package "$PKG" 2>/dev/null | sed -n 's/^ *versionName=//p' | head -1 | tr -d '\r'
}

# ---- 一次完整尝试 ----
# 返回 0=已装目标版本  1=列表里没有  2=打不开界面  3=装到的是旧版本
attempt_once(){
  open_install_page || return 2
  install_from_list || return 1
  if [ -n "$VER" ]; then
    local v; v="$(installed_version)"
    [ "$v" = "$VER" ] || { echo "   装到的是 v${v:-?},不是目标 v$VER"; return 3; }
  fi
  return 0
}

# ---- 主流程 ----
echo "==> 目标: ${LABEL}  (${PKG:-未知包名} v${VER:-?})  @ $TV"
push_apk

echo "==> 打开 安全卫士 / 应用管理器"
attempt_once; rc=$?

if [ $rc -ne 0 ]; then
  case $rc in
    1) echo "   列表里没有它 —— TGuard 的扫描结果有缓存,清掉后重建" ;;
    3) echo "   列表里是缓存中的旧条目 —— 清掉缓存后重建" ;;
    2) exit 1 ;;
  esac
  # 清 TGuard 数据会重置它自己的设置(应用自动卸载、定期清理等),
  # 但这是除「重插 U 盘」和「重启电视」之外唯一能重建扫描缓存的途径。
  A "pm clear com.tcl.guard" >/dev/null 2>&1
  sleep 3

  echo "==> 重试"
  attempt_once; rc=$?
  if [ $rc -ne 0 ]; then
    echo "!! 重试仍失败 (rc=$rc)" >&2
    echo "   当前焦点: $(focused_label)" >&2
    echo "   界面: $(ui_text | cut -c1-200)" >&2
    exit 1
  fi
fi

echo
echo "==> 结果"
if [ -n "$PKG" ] && A pm list packages | grep -q "package:$PKG"; then
  echo "  已安装"
  A dumpsys package "$PKG" 2>/dev/null \
    | grep -E 'versionName|primaryCpuAbi|installerPackageName|lastUpdateTime' | sed 's/^ */  /'
else
  echo "  未安装"
fi

#!/usr/bin/env bash
#
# 给 Pico 的「2D 应用面板」定向注入按键 / 触摸
#
# 为什么需要它
#   Pico 给**每个应用**建一个独立虚拟 display(uniqueId 形如
#   `virtual:com.picovr.systemext,1000,NS_APP[<pkg>],0`),而 `input` 默认打到
#   display 0(也就是 com.pvr.vrshell)。所以裸 `input keyevent` **到不了你的应用**,
#   只是白按 —— 不报错,也没反应。
#
#   必须显式指定 `-d <该应用的 displayId>`,而且那个 displayId **每次启动应用都会变**
#   (实测同一个包一轮会话里见过 24/36/38/40/42/44/46/50),不能记下来复用。
#   用错了的表现是 WindowManager 静默丢弃:
#       W WindowManager: Dropping key targeting non-focused display #24 keyCode=KEYCODE_DPAD_DOWN
#
# 用法
#   bash tools/pico-panel.sh <package.id> awake                  # 拉起应用 + 保持头显不睡
#   bash tools/pico-panel.sh <package.id> display                # 只打印解析出的 displayId
#   bash tools/pico-panel.sh <package.id> key   <KEYCODE...>     # 定向按键,可给多个
#   bash tools/pico-panel.sh <package.id> tap   <x> <y>          # 定向点击
#   bash tools/pico-panel.sh <package.id> swipe <x1> <y1> <x2> <y2> [毫秒]
#
#   加 `--awake`(放任意位置)会在动作前先把 `pvr.factorytest.never.sleep` 置 1。
#   见 docs/04-pico4-notes.md「不戴头显 10 秒就休眠」。
#
# 验收
#   注入是否真的送达,用「自截图前后对比」判断,不要靠感觉:
#     bash tools/ui-dump.sh <pkg> "$PICO_ADDR" /tmp/a.png
#     bash tools/pico-panel.sh <pkg> --awake key KEYCODE_DPAD_DOWN
#     bash tools/ui-dump.sh <pkg> "$PICO_ADDR" /tmp/b.png
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

usage(){
  cat <<'USAGE'
用法:
  bash tools/pico-panel.sh <package.id> awake
  bash tools/pico-panel.sh <package.id> display
  bash tools/pico-panel.sh <package.id> key   <KEYCODE...>
  bash tools/pico-panel.sh <package.id> tap   <x> <y>
  bash tools/pico-panel.sh <package.id> swipe <x1> <y1> <x2> <y2> [毫秒]
  (任意位置可加 --awake)
USAGE
  exit 2
}

DEV="$PICO_ADDR"
AWAKEN=0
PKG=""; CMD=""
REST=()
for a in "$@"; do
  case "$a" in
    --awake) AWAKEN=1 ;;
    *) if   [ -z "$PKG" ]; then PKG="$a"
       elif [ -z "$CMD" ]; then CMD="$a"
       else REST+=("$a"); fi ;;
  esac
done
[ -n "$PKG" ] && [ -n "$CMD" ] || usage

A(){ timeout 60 adb -s "$DEV" shell "$@" </dev/null 2>&1 | tr -d '\r'; }

if ! adb devices | awk -v d="$DEV" '$1==d && $2=="device"' | grep -q .; then
  echo "设备 $DEV 未连接。先跑: bash tools/devices.sh" >&2
  exit 1
fi

# 唯一权威来源:dumpsys display 的 mViewports,形如
#   DisplayViewport{type=VIRTUAL, valid=true, displayId=46,
#     uniqueId='virtual:com.picovr.systemext,1000,NS_APP[<pkg>],0', ...}
# 同一个包可能有多条(如 settings 有 ,0 和 ,1),取最后一条 = 最新建的。
display_id(){
  A "dumpsys display" \
    | grep -oE "displayId=[0-9]+, uniqueId='virtual:[^']*NS_APP\[$PKG\]," \
    | sed 's/^displayId=//' | cut -d, -f1 | tail -1
}

panel_state(){
  A "dumpsys display" | grep "DisplayDeviceInfo{\"NS_APP\[$PKG\]\"" \
    | grep -oE 'state [A-Z]+' | head -1
}

keep_awake(){
  # 非持久属性,重启自动恢复 0,不留后遗症。
  # 注意:只设 persist.pvr.sleep_by_static=0 没用,实测照样睡,必须是这个。
  A "setprop pvr.factorytest.never.sleep 1" >/dev/null
}

case "$CMD" in
  awake)
    keep_awake
    A "input keyevent KEYCODE_WAKEUP" >/dev/null
    echo "==> 保持唤醒已开,拉起 $PKG"
    A "monkey -p $PKG -c android.intent.category.LAUNCHER 1" >/dev/null 2>&1
    sleep 3
    DID="$(display_id)"
    [ -n "$DID" ] || { echo "!! 没找到 $PKG 的面板 display。应用起来了吗?" >&2; exit 1; }
    echo "  面板 displayId=$DID  $(panel_state)"
    exit 0
    ;;
  display)
    DID="$(display_id)"
    [ -n "$DID" ] || { echo "!! 没找到 $PKG 的面板 display —— 应用没在前台?" >&2; exit 1; }
    echo "$DID"; exit 0
    ;;
esac

[ "$AWAKEN" = 1 ] && keep_awake

DID="$(display_id)"
[ -n "$DID" ] || { echo "!! 没找到 $PKG 的面板 display —— 先跑: $0 $PKG awake" >&2; exit 1; }

STATE="$(panel_state)"
if [ "$STATE" != "state ON" ]; then
  echo "!! 面板是 ${STATE:-未知}(不是 ON)。多半是头显睡了 —— 加 --awake,或先跑 $0 $PKG awake" >&2
  exit 1
fi

case "$CMD" in
  # 参数顺序有讲究:`input [<source>] [-d ID] <command>`,
  # 写成 `input -d 46 dpad keyevent ...` 会报 Unknown command: dpad
  key)
    [ ${#REST[@]} -gt 0 ] || usage
    for k in "${REST[@]}"; do A "input -d $DID keyevent $k"; done
    ;;
  tap)
    [ ${#REST[@]} -ge 2 ] || usage
    A "input -d $DID tap ${REST[0]} ${REST[1]}"
    ;;
  swipe)
    [ ${#REST[@]} -ge 4 ] || usage
    A "input -d $DID swipe ${REST[0]} ${REST[1]} ${REST[2]} ${REST[3]} ${REST[4]:-300}"
    ;;
  *) usage ;;
esac

echo "==> 已向 display $DID 注入 $CMD(面板 $STATE)"
echo "    送达验证:再跑一次 tools/ui-dump.sh 对比图片;"
echo "    若被丢弃,logcat 里会有 'Dropping key targeting non-focused display'。"

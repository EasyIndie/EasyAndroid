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
# ⚠️ 2026-09-16 实测补充(Windows 主机复验时发现):
#   · 一次 input 传 ≥4 个 keyevent 会丢键(7 连发只生效 2 发,≤3 发可靠)
#     → key_rep 与长导航序列都分批发
#   · TGuard 列表是渐进解析的:条目先显示文件名,后台解析完才换成应用名,
#     且解析完会重排(新文件按修改时间倒序插到列表顶部)
#     → match_here 同时匹配应用名和 ${PKG}-*.apk 文件名,解析没完成也能点
#   · pm clear com.tcl.guard 会让 U 盘全部 APK 重新解析+重排(约 1~2 分钟),
#     安装窗口内列表根本不稳定 → 默认不 clear,只留作重试轮的兜底
#
# 用法
#   bash tools/tv-install.sh <apk>                # 安装 + 启动 + 自截图
#   bash tools/tv-install.sh <apk> --no-launch    # 只安装
#   bash tools/tv-install.sh <apk> --no-shot      # 装完不截图
#   bash tools/tv-install.sh <apk> --shot-out out.png
#   LABEL=MyApp bash tools/tv-install.sh <apk>
#   PKG=com.x.y VER=1.2.3 ACTIVITY=... bash tools/tv-install.sh <apk>
#     (没有 aapt2 的机器上手动给元信息,见下方「APK 元信息」一节)
#
# 装完会调用 tools/ui-dump.sh 截一张真实渲染的图(需要 debug 构建里的钩子,
# 见 docs/07-debug-ui-capture.md)。没有钩子时只提示,不影响安装结果。
#
# 跨平台:Windows 原生 / WSL2 / Linux 均可,差异见 tools/_common.sh 顶部。
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
[ -n "$ADB" ] || { echo "!! 找不到可用的 adb(见 tools/README.md)" >&2; exit 1; }

# aapt2 用来读 APK 的 label / 包名 / 版本。Windows 上是 aapt2.exe。
AAPT2=""
for bt in "$ANDROID_HOME"/build-tools/*/; do
  for cand in "${bt}aapt2" "${bt}aapt2.exe"; do
    if [ -x "$cand" ]; then AAPT2="$cand"; break 2; fi
  done
done
if [ -z "$AAPT2" ] && command -v aapt2 >/dev/null 2>&1; then AAPT2="$(command -v aapt2)"; fi
TV="${TV:-$TV_ADDR}"

if ! adb_online "$TV"; then
  echo "电视 $TV 不在线。先跑: bash tools/devices.sh" >&2
  echo "  (TCL 的侧载通道依赖界面操作,设备必须在线且能读 UI 树)" >&2
  exit 1
fi

A(){ run_timeout 40 "$ADB" -s "$TV" shell "$@" </dev/null 2>&1; }

# 收尾时把自己在设备上留的工作文件清掉 —— dumpui 会把 UI 树落在 /sdcard/_ui.xml,
# 每条路径(含报错退出)都不应该把它留在电视上。
trap 'A "rm -f /sdcard/_ui.xml" >/dev/null 2>&1' EXIT
# ⚠️ `input` 是 Java 程序,每次启动 ~0.9 秒。单发 13 个键要 11.7 秒,
# 合成一次调用只要 ~1 秒,所以统一走 keys()(空格分隔的一串 keycode)。
keys(){ A input keyevent $1 >/dev/null; sleep "${2:-0.3}"; }
# 但一次 input 传太多键会丢键(实测 7 连发只生效 2 发,≤3 发可靠),
# key_rep 分批,每批最多 3 键。
key_rep(){ local k="$1" n="$2" d="${3:-0.5}"
  [ "$n" -gt 0 ] 2>/dev/null || return 0
  while [ "$n" -gt 0 ]; do
    local i=0 args=""
    while [ "$i" -lt 3 ] && [ "$n" -gt 0 ]; do args+="$k "; i=$((i+1)); n=$((n-1)); done
    keys "$args" "$d"
  done; }

# ---- APK 元信息 ----
# aapt2 是捷径不是硬依赖:机器上没装 build-tools 时,可用环境变量手动给元信息
#   PKG=... VER=... ACTIVITY=... [LABEL=...] bash tools/tv-install.sh <apk>
# PKG 必须给(缺它没法装);VER 缺省则跳过装后版本校验;ACTIVITY 缺省则装完不自动启动。
badging(){ [ -n "$AAPT2" ] && "$AAPT2" dump badging "$APK" 2>/dev/null; return 0; }
[ -n "$AAPT2" ] || [ -n "${PKG:-}" ] || {
  echo "!! 找不到 aapt2,也没有手动指定 PKG。二选一:" >&2
  echo "   a. 装 Android SDK build-tools,或设 ANDROID_HOME 指向 SDK;" >&2
  echo "   b. PKG=com.x.y [VER=1.2.3] [ACTIVITY=...] bash tools/tv-install.sh <apk>" >&2
  exit 1
}
LABEL="${LABEL:-$(badging | sed -n "s/^application-label:'\(.*\)'/\1/p" | head -1)}"
LABEL="${LABEL:-双端演示}"
PKG="${PKG:-$(badging | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)}"
VER="${VER:-$(badging | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" | head -1)}"
ACTIVITY="${ACTIVITY:-$(badging | sed -n "s/^launchable-activity: name='\([^']*\)'.*/\1/p" | head -1)}"

# ---- UI 读取 ----
UI_XML="$TMP/_ui.xml"
dumpui(){
  A uiautomator dump /sdcard/_ui.xml >/dev/null 2>&1
  # 本机侧路径必须过 win_of:adb.exe 是原生程序,不认 Git Bash 的 /e/... 形式
  run_timeout 30 "$ADB" -s "$TV" pull /sdcard/_ui.xml "$(win_of "$UI_XML")" </dev/null >/dev/null 2>&1
}
# 一次 dump 同时拿到「焦点项的标签」和「详情面板里的版本号」
focus_info(){
  dumpui
  [ -n "$PY" ] || { echo '|'; return; }
  "$PY" - "$(pyfile "$UI_XML")" <<'PYEOF'
import re, sys
try: s = open(sys.argv[1], encoding='utf-8').read()
except Exception: print('|'); raise SystemExit
fx = None; nodes = []; sel_texts = []
for x in re.findall(r'<node[^>]*>', s):
    b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', x)
    if not b: continue
    bb = tuple(map(int, b.groups()))
    t = re.search(r'text="([^"]*)"', x)
    txt = t.group(1) if t else ''
    if re.search(r'focused="true"', x): fx = bb
    if re.search(r'selected="true"', x) and txt.strip(): sel_texts.append(txt)
    if txt.strip(): nodes.append((txt, bb))
def clean(t):
    t = t.strip()
    return '' if (not t or re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', t)
                  or t in ('本机已安装', '/')) else t
# 焦点项标签:优先 selected="true" 的列表项文本 —— TGuard 有两种渲染态
# (文本随选中卡片重排 / 文本留在列表原位),只有 selected 在两种态下都可靠;
# 兜底才是 focused 卡片 bounds 内的文本。selected 集合里混着角标(本机已安装),
# 逐个清洗取第一个有效文本。
label = ''
for t in sel_texts:
    label = clean(t)
    if label: break
if not label and fx:
    x1, y1, x2, y2 = fx; cands = []
    for txt, (a1, b1, a2, b2) in nodes:
        if a1 >= x1 and a2 <= x2 and b1 >= y1 and b2 <= y2:
            t = clean(txt)
            if t: cands.append(t)
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
  [ -n "$PY" ] || { echo ''; return; }
  "$PY" - "$(pyfile "$UI_XML")" <<'PYEOF'
import re, sys
try: s = open(sys.argv[1], encoding='utf-8').read()
except Exception: raise SystemExit
seen = []
for x in re.findall(r'<node[^>]*>', s):
    t = re.search(r'text="([^"]*)"', x)
    if t and t.group(1) and t.group(1) not in seen: seen.append(t.group(1))
print(' / '.join(seen))
PYEOF
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
  local stamp; stamp="$(file_mtime "$APK")"
  local name="${PKG:-app}-${VER:-0}-${stamp}.apk"
  A "rm -f $APK_DIR/${PKG:-app}-*.apk" >/dev/null 2>&1 || true
  echo "==> 推送 APK 到 $APK_DIR/$name"
  # APK 路径同样过 win_of(用户传 /e/... 绝对路径时 adb.exe 才能读)
  run_timeout 120 "$ADB" -s "$TV" push "$(win_of "$APK")" "$APK_DIR/$name" </dev/null 2>&1 | tail -1
}

# ---- 屏保判断 ----
is_dreaming(){ case "$(foreground)" in *Dream*) return 0 ;; *) return 1 ;; esac; }

# 屏幕中心——兜底用的指针事件落点。wm size 可能同时报 Physical/Override 两行,取最后一行的。
screen_center(){
  local s; s="$(A wm size 2>/dev/null | tr -d '\r' \
        | sed -n 's/.*size: *\([0-9]*\)x\([0-9]*\).*/\1 \2/p' | tail -1)"
  [ -n "$s" ] || s="1920 1080"
  echo $(( ${s% *} / 2 )) $(( ${s#* } / 2 ))
}

# ---- 界面状态复位 ----
# 屏保会吞掉 am start;上一次的「应用安装已完成」弹窗会把后续按键全带偏。
# BACK 是幂等的,直接按两次比 dump 一次判断更便宜。
reset_ui_state(){
  keys "KEYCODE_WAKEUP KEYCODE_BACK KEYCODE_BACK KEYCODE_HOME" 1.2

  # ⚠️ 兜底:实测撞到过一次「屏保把之后所有按键全吞掉」的状态 ——
  # WAKEUP / BACK / HOME / DPAD_CENTER / POWER 连试 15 秒均无效,
  # 但发一个【指针事件】立刻恢复。
  # TCL 遥控走的是 IR 触控(gIrTouch_Mouse,Source 含 SOURCE_MOUSE|SOURCE_TOUCHPAD),
  # 屏保只认指针。复现条件没定位到(静置 205 秒、长按 POWER 都没复现),
  # 所以这段是防御性的:只在确实还是 Dream 时才发,避免误点界面。
  # 它值一次偶发失败 —— 卡在那个状态时整个安装链路会失败(2026-09 实测过一次)。
  if is_dreaming; then
    A input tap $(screen_center) >/dev/null 2>&1
    sleep 1.5
    keys "KEYCODE_BACK KEYCODE_HOME" 1
  fi
}

# ---- 打开「应用安装」页 ----
open_install_page(){
  reset_ui_state
  # 不用 am start -S:强杀 TGuard 会让列表条目重新渐进入库(几分钟),
  # 进程活着时重新 am start,列表状态和解析缓存都还在,焦点还回到列表顶部
  A am start -n com.tcl.guard/.appmanager.activity.AppManagerActivity >/dev/null
  sleep 2
  # 左侧栏: 应用管理 / 应用卸载 / 应用安装(UP 到顶会截断)
  # 序列拆批发(一次 input ≥4 键会丢键,见文件头「实测补充」)
  keys "KEYCODE_DPAD_LEFT" 0.6
  keys "KEYCODE_DPAD_UP KEYCODE_DPAD_UP" 0.6
  keys "KEYCODE_DPAD_DOWN KEYCODE_DPAD_DOWN" 0.6
  keys "KEYCODE_DPAD_CENTER" 1.2
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
  # label 可能是解析完成的应用名(双端演示),也可能是解析前的文件名
  # (TGuard 渐进解析,见文件头「实测补充」)。两种都认,解析没完成也能点。
  case "$label" in
    "$LABEL"|${PKG:-__none__}-*.apk|._${PKG:-__none__}-*.apk) ;;
    *) return 1 ;;
  esac
  # ver 为空或 "/"(详情面板还没解析出来的占位符)都放行,
  # 装完有 versionName 校验兜底;只有 ver 非空且对不上才跳过同名旧版本。
  if [ -n "$VER" ] && [ -n "$ver" ] && [ "$ver" != "/" ] && [ "$ver" != "$VER" ]; then
    echo "   跳过同名旧版本 (v${ver:-?})"; return 1
  fi
  echo "   焦点已落在「$label」 v${ver:-?}"
  keys "KEYCODE_DPAD_CENTER" 0.4
  return 0
}
# 等列表稳定:连续两次 dump 的可见文本集合一致才算稳定。
# am start 会重建 Activity 触发列表重载,条目渐进出现、顺序漂移,
# 不稳定时扫了白扫(2026-09-16 实测:重载期 3 轮×26 项全部 miss)。
wait_list_settled(){
  local prev="" cur="" i
  for i in $(seq 1 30); do
    dumpui
    cur="$("$PY" - "$(pyfile "$UI_XML")" <<'PYEOF'
import re, sys
try: s = open(sys.argv[1], encoding='utf-8').read()
except Exception: print(''); raise SystemExit
ts = sorted({t.group(1).strip()
             for t in (re.search(r'text="([^"]*)"', x)
                       for x in re.findall(r'<node[^>]*>', s))
             if t and t.group(1).strip()})
print('|'.join(ts))
PYEOF
)"
    if [ -n "$cur" ] && [ "$cur" = "$prev" ]; then return 0; fi
    prev="$cur"
    sleep 3
  done
  return 0   # 超时放弃等待,扫描自带多轮兜底
}

locate_and_trigger(){
  local i round pos
  wait_list_settled
  for round in 1 2; do
    if [ "$round" -gt 1 ]; then
      # 重扫只等待,不重新进页 —— 再 am start 一次又会触发列表重载
      echo "   第 $((round - 1)) 轮没找到,等 8s 重扫"
      sleep 8
    fi
    if [ "$round" = 1 ] && [ -f "$POS_FILE" ]; then
      pos="$(cat "$POS_FILE" 2>/dev/null)"
      if [ -n "$pos" ] && [ "$pos" -gt 1 ] 2>/dev/null; then
        key_rep KEYCODE_DPAD_DOWN "$((pos - 1))" 0.4
        if match_here; then return 0; fi
        echo "   位置缓存失效,从头扫"
        key_rep KEYCODE_DPAD_UP "$pos" 0.4
      fi
    fi
    for i in $(seq 1 26); do
      if match_here; then echo "$i" > "$POS_FILE" 2>/dev/null || true; return 0; fi
      keys "KEYCODE_DPAD_DOWN" 0.4
    done
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
sleep 2   # 给 TGuard 一点时间把新文件插进列表(按修改时间倒序,新文件在顶部)

echo "==> 打开 安全卫士 / 应用管理器"
open_install_page
# 注意:这里【不做】pm clear。清了缓存 TGuard 会把 U 盘全部 APK 重新解析+重排,
# 约 1~2 分钟内列表条目全是文件名且顺序在变,定位必失败(2026-09-16 实测)。
# 热缓存下新文件插在列表顶部,从顶扫 1~2 项就能命中。pm clear 留给重试轮兜底。

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
  echo "   重来一次(清缓存重建列表后位置会变)"
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
    : "${SHOT_OUT:=$TMP/ui-dump-$(printf '%s' "$PKG" | tr '.' '_').png}"
    if ! bash "$_TOOLS_DIR/ui-dump.sh" "$PKG" "$TV" "$SHOT_OUT" 2>"$TMP/_tvinstall_shot.err"; then
      echo "  (跳过 —— 多半是 release 包,没有 debug 自截图钩子;见 docs/07)" >&2
      sed 's/^/    /' "$TMP/_tvinstall_shot.err" | head -6 >&2
    fi
  fi
fi

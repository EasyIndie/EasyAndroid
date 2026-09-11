#!/usr/bin/env bash
#
# 把 APK 装到 TCL 电视上
#
# 为什么需要这个脚本
#   TCL 在当前固件的 system_server 里打了补丁(OverseasAppConfig),导致
#   adb install / pm install / install-create --skip-verification 全部返回
#   INSTALL_FAILED_VERIFICATION_FAILURE,而且关掉 AOSP 的 verifier 开关
#   (verifier_verify_adb_installs / package_verifier_enable)无效。
#
#   唯一可用通道是 TGuard 的图形化安装器:
#     安全卫士 -> 应用管理 -> 应用安装 -> 选 APK -> 系统安装器确认
#   走这条路 installer 会记成 com.android.packageinstaller,是 TCL 认可的。
#
#   另外注意: 系统安装器的 InstallStart 只接受 content:// 的 URI,
#   所以也没法用 `am start` 从命令行把 APK 丢给它。
#
# 用法
#   bash tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk
#   LABEL=双端演示 TV=192.0.2.11:5555 bash tools/tv-install.sh <apk>   # 覆盖默认设备
#
# 设备地址默认从 tools/device.env 读(见 device.env.example)。
#
# 全程只用 adb + uiautomator 读界面文本,不用视觉模型。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# aapt2 用来从 APK 里读 label / package name
for bt in "$ANDROID_HOME"/build-tools/*/; do
  [ -x "$bt/aapt2" ] && export PATH="$bt:$PATH" && break
done

TV="${TV:-$TV_ADDR}"
APK="${1:-}"
[ -n "$APK" ] || { echo "用法: $0 <apk路径>" >&2; exit 2; }
[ -f "$APK" ] || { echo "找不到 APK: $APK" >&2; exit 2; }

A(){ timeout 40 adb -s "$TV" shell "$@" </dev/null 2>&1; }
key(){ A input keyevent "$1" >/dev/null; sleep "${2:-1}"; }
dumpui(){ A uiautomator dump /sdcard/_ui.xml >/dev/null 2>&1
          timeout 30 adb -s "$TV" pull /sdcard/_ui.xml /tmp/_ui.xml </dev/null >/dev/null 2>&1; }

# 界面上的所有文案(便于人读)
ui_text(){ dumpui; python3 -c "
import re
try: s=open('/tmp/_ui.xml',encoding='utf-8').read()
except: raise SystemExit
o=[]
for x in re.findall(r'<node[^>]*>',s):
    t=re.search(r'text=\"([^\"]*)\"',x)
    if t and t.group(1): o.append(t.group(1))
print(' / '.join(o))
"; }

# 当前焦点所在的列表项标签(focused 容器里包着的 text)
focused_label(){ dumpui; python3 -c "
import re
try: s=open('/tmp/_ui.xml',encoding='utf-8').read()
except: print(''); raise SystemExit
nodes=re.findall(r'<node[^>]*>',s)
def bounds(x):
    b=re.search(r'bounds=\"\[(\d+),(\d+)\]\[(\d+),(\d+)\]\"',x)
    return tuple(map(int,b.groups())) if b else None
fx=None
labels=[]
for x in nodes:
    b=bounds(x)
    if not b: continue
    t=re.search(r'text=\"([^\"]*)\"',x)
    if re.search(r'focused=\"true\"',x): fx=b
    if t and t.group(1): labels.append((t.group(1),b))
if not fx: print(''); raise SystemExit
x1,y1,x2,y2=fx
cands=[]
for txt,(a1,b1,a2,b2) in labels:
    if a1>=x1 and a2<=x2 and b1>=y1 and b2<=y2:
        t=txt.strip()
        # 排除日期 / 状态标记,只留应用名
        if not t or re.fullmatch(r'\d{4}\.\d{2}\.\d{2}', t): continue
        if t in ('本机已安装',): continue
        cands.append(t)
print(cands[0] if cands else '')
"; }

wait_text(){ local pat="$1" t="${2:-20}" i
  for ((i=0;i<t;i++)); do ui_text | grep -qE "$pat" && return 0; sleep 1; done
  return 1; }

# 目标应用名: 优先取环境变量,否则从 APK 里读
if [ -z "${LABEL:-}" ]; then
  LABEL="$(aapt2 dump badging "$APK" 2>/dev/null | sed -n "s/^application-label:'\(.*\)'/\1/p" | head -1)"
fi
LABEL="${LABEL:-双端演示}"
PKG="$(aapt2 dump badging "$APK" 2>/dev/null | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -1)"
echo "==> 目标: ${LABEL}  (${PKG:-未知包名})  @ $TV"

A input keyevent KEYCODE_WAKEUP >/dev/null

echo "==> 推送 APK 到 /sdcard"
adb -s "$TV" push "$APK" "/sdcard/$(basename "$APK")" </dev/null 2>&1 | tail -1

echo "==> 打开 安全卫士 / 应用管理器"
A input keyevent KEYCODE_HOME >/dev/null; sleep 2
A am start -S -n com.tcl.guard/.appmanager.activity.AppManagerActivity >/dev/null
sleep 6
ui_text | grep -qE '应用管理|应用卸载|应用安装' || { echo "  !! 应用管理器没打开"; exit 1; }

echo "==> 切到「应用安装」"
# 左侧栏顺序: 应用管理 / 应用卸载 / 应用安装 ; UP 会截断所以先归顶再下移两位
key KEYCODE_DPAD_LEFT 2
for i in 1 2 3 4 5; do key KEYCODE_DPAD_UP 1; done
key KEYCODE_DPAD_DOWN 1
key KEYCODE_DPAD_DOWN 1
key KEYCODE_DPAD_CENTER 4
wait_text 'SDCARD|已完成扫描|确认键安装应用' 15 || { echo "  !! 没进到应用安装页"; exit 1; }

echo "==> 进入存储源并扫描"
key KEYCODE_DPAD_RIGHT 2
key KEYCODE_DPAD_CENTER 8
wait_text '确认键安装应用|已完成扫描' 30 || echo "  (等扫描完成超时,继续尝试)"
sleep 3

echo "==> 在列表里定位「$LABEL」"
for i in $(seq 1 20); do key KEYCODE_DPAD_UP 1; done   # 先归顶
found=0
for i in $(seq 1 40); do
  cur="$(focused_label)"
  if [ "$cur" = "$LABEL" ]; then found=1; break; fi
  key KEYCODE_DPAD_DOWN 1
done
if [ "$found" != 1 ]; then
  echo "  !! 列表里没找到「$LABEL」(当前焦点: $(focused_label))"
  echo "     界面: $(ui_text | cut -c1-160)"
  exit 1
fi
echo "  焦点已落在「$LABEL」"

echo "==> 触发安装 + 过两道确认框"
key KEYCODE_DPAD_CENTER 6
for round in 1 2; do
  if wait_text '是否继续安装|要安装此应用吗|是否安装' 20; then
    key KEYCODE_DPAD_RIGHT 2
    key KEYCODE_DPAD_CENTER 8
  fi
done

if wait_text '安装完成|已安装|立即体验|打开' 25; then
  echo "  安装流程已结束"
fi

echo
echo "==> 结果"
A pm list packages | grep -q "${PKG:-com.example.dualdemo}" && echo "  已安装" || echo "  未安装"
A dumpsys package "${PKG:-com.example.dualdemo}" 2>/dev/null \
  | grep -E 'versionName|primaryCpuAbi|installerPackageName|firstInstallTime' | sed 's/^ */  /'

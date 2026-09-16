#!/usr/bin/env bash
# Pico 4 重启后恢复「无线调试」
#
# 背景: Pico 的 adb 端口只写在运行时属性 service.adb.tcp.port 里,重启即丢;
#       persist.adb.tcp.port 在 shell 权限下写不进去(需要 root)。
#       Android TV 那台写进了 persist,所以重启后仍然无线可达,只有 Pico 需要跑这个。
#       详见 docs/02-adb-multi-device.md
#
# 前置: USB 数据线把 Pico 连到本机的 Windows 主机。
#       · WSL2 没有 USB 总线,插在 Windows 上的设备 WSL 看不见 —— 所以这一步
#         必须由 Windows 版 adb 完成(脚本会自己找)。
#       · Windows 原生(Git Bash)上 $ADB 本身就是 adb.exe,不需要另拉一份。
#
# 用法: bash tools/pico-usb.sh
#
# 跨平台:Windows 原生 / WSL2 均可,差异见 tools/_common.sh 顶部。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

# USB 侧必须用 Windows 版 adb —— WSL2 里没有 USB 总线。
if [ ! -x "$WINADB" ]; then
  if [ "$IS_WINDOWS" = 1 ] && [ -n "$ADB" ]; then
    WINADB="$ADB"                     # Windows 原生:$ADB 就是 adb.exe
  else
    echo "找不到 Windows 版 adb: $WINADB" >&2
    echo "先跑: bash tools/fetch-platform-tools.sh" >&2
    exit 1
  fi
fi

# 端口只在「WSL + Windows 版 adb 并存」时才需要错开 ——
# WSL 是 mirrored 网络,两边会抢同一个 localhost:5037。
# Windows 原生上只有一个 adb,直接用默认端口更省事。
if [ "$IS_WINDOWS" = 1 ]; then
  WPORT=""
else
  WPORT="-P $WINADB_PORT"
fi

wadb(){ "$WINADB" $WPORT "$@" 2>&1 | tr -d '\r'; }

echo "==> 平台 $PLATFORM  ·  Windows 侧 adb = $WINADB ${WPORT:+($WPORT)}"
wadb start-server >/dev/null

echo "==> 检查 USB 上的 Pico"
if ! wadb devices | awk 'NR>1 && $2=="device"{f=1} END{exit !f}'; then
  {
    echo "    USB 上没检测到设备。请确认:"
    echo "      1. USB 数据线已插好(不是只能充电的线)"
    echo "      2. 头显里已点「允许 USB 调试」"
    echo "      3. Pico 设置 -> 通用 -> 开发者 里 USB 调试已开"
  } >&2
  wadb devices -l >&2
  exit 1
fi
wadb devices -l | sed 's/^/  /'

echo "==> 切换 adbd 到 TCP 模式 port 5555"
wadb tcpip 5555 | sed 's/^/  /'
sleep 3

echo
echo "==> 无线连入 $PICO_ADDR"
# 不复位 adb server,否则会把 TV 那条连接一起断掉
adb_connect_all

if adb_online "$PICO_ADDR"; then
  echo "✅ 已连接。现在可以拔掉 USB 线(Pico 走无线即可)。"
else
  echo "!! 还没连上,再试一次 connect:" >&2
  "$ADB" disconnect "$PICO_ADDR" >/dev/null 2>&1 || true
  "$ADB" connect "$PICO_ADDR" >&2 || true
fi

echo
"$ADB" devices -l

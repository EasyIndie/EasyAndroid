#!/usr/bin/env bash
# Pico 4 重启后恢复「无线调试」
#
# 背景: Pico 的 adb 端口只写在运行时属性 service.adb.tcp.port 里,重启即丢;
#       persist.adb.tcp.port 在 shell 权限下写不进去(需要 root)。
#       Android TV 那台写进了 persist,所以重启后仍然无线可达,只有 Pico 需要跑这个。
#       详见 docs/02-adb-multi-device.md
#
# 前置: USB 数据线把 Pico 连到本机的 Windows 主机(不是 WSL —— WSL2 没有 USB 总线)。
#       首次需要先跑: bash tools/fetch-platform-tools.sh
#
# 用法: bash tools/pico-usb.sh
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if [ ! -x "$WINADB" ]; then
  echo "找不到 Windows 版 adb: $WINADB" >&2
  echo "先跑: bash tools/fetch-platform-tools.sh" >&2
  exit 1
fi

echo "==> 启动 Windows 侧 adb server (port $WINADB_PORT)"
# 不能用默认 5037: WSL 是 mirrored 网络,会和 Linux 侧 adb server 抢同一个 localhost 端口
"$WINADB" -P "$WINADB_PORT" start-server 2>&1 | tr -d '\r'

echo "==> 检查 USB 上的 Pico"
if ! "$WINADB" -P "$WINADB_PORT" devices | tr -d '\r' | grep -q "device$"; then
  {
    echo "    USB 上没检测到设备。请确认:"
    echo "      1. USB 数据线已插好(不是只能充电的线)"
    echo "      2. 头显里已点「允许 USB 调试」"
    echo "      3. Pico 设置 -> 通用 -> 开发者 里 USB 调试已开"
  } >&2
  "$WINADB" -P "$WINADB_PORT" devices -l | tr -d '\r' >&2
  exit 1
fi

echo "==> 切换 adbd 到 TCP 模式 port 5555"
"$WINADB" -P "$WINADB_PORT" tcpip 5555 2>&1 | tr -d '\r'
sleep 3

echo "==> 从 WSL 侧无线连入"
# 不复位 adb server,否则会把 TV 那条连接一起断掉
adb start-server >/dev/null 2>&1 || true
adb connect "$PICO_ADDR" 2>&1

echo
echo "完成。现在可以拔掉 USB 线(Pico 走无线即可)。"
adb devices -l

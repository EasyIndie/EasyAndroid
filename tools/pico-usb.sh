#!/usr/bin/env bash
# Pico 4 重启后恢复「无线调试」
#
# 背景: Pico 的 adb 端口只在 service.adb.tcp.port 里(运行时属性),重启即丢;
#       而 persist.adb.tcp.port 无法用 shell 写入(需要 root)。电视那台写进了
#       persist, 所以电视重启后仍然无线可达, 只有 Pico 需要跑这个脚本。
#
# 前置: 用 USB 数据线把 Pico 连到本机的 Windows 主机(不是 WSL)。
# 用法: bash tools/pico-usb.sh

PICO_IP="${PICO_IP:-192.0.2.29}"
WINADB="${WINADB:-$(cd "$(dirname "$0")" && pwd)/platform-tools/adb.exe}"
PORT=15037   # 不能用默认 5037: WSL 是 mirrored 网络, 会和 Linux 侧 adb server 抢端口

if [ ! -x "$WINADB" ]; then
  echo "找不到 Windows 版 adb: $WINADB" >&2
  echo "先跑: bash tools/fetch-platform-tools.sh" >&2
  exit 1
fi

echo "==> 启动 Windows 侧 adb server (port $PORT)"
"$WINADB" -P "$PORT" start-server 2>&1 | tr -d '\r'

echo "==> 检查 USB 上的 Pico"
if ! "$WINADB" -P "$PORT" devices | tr -d '\r' | grep -q "device$"; then
  echo "    USB 上没检测到设备。请确认:" >&2
  echo "      1. USB 数据线已插好(不是只充电的线)" >&2
  echo "      2. 头显里已点「允许 USB 调试」" >&2
  echo "      3. Pico 设置 -> 通用 -> 开发者 里 USB 调试已开" >&2
  "$WINADB" -P "$PORT" devices -l | tr -d '\r'
  exit 1
fi

echo "==> 切换 adbd 到 TCP 模式 port 5555"
"$WINADB" -P "$PORT" tcpip 5555 2>&1 | tr -d '\r'
sleep 3

echo "==> 从 WSL 侧无线连入"
export PATH=/opt/android-sdk/platform-tools:$PATH
# 不复位 adb server, 否则会把电视那条连接一起断掉
adb start-server >/dev/null 2>&1 || true
adb connect "$PICO_IP:5555" 2>&1

echo
echo "完成。现在可以拔掉 USB 线(Pico 用无线即可)。"
adb devices -l

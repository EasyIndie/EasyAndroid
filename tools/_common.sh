#!/usr/bin/env bash
# 各脚本共用的载入逻辑。不要直接执行,用 `source`。
#
# 作用:
#   1. 读 tools/device.env(本地私有,已 gitignore)拿到真实设备地址
#   2. 没有的话回落到 RFC 5737 文档保留地址(192.0.2.0/24),此时脚本会连不上,
#      属于预期行为 —— 提醒你该创建 device.env 了
#   3. 统一补好 PATH / JAVA_HOME

_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$_TOOLS_DIR/device.env" ]; then
  # shellcheck disable=SC1091
  . "$_TOOLS_DIR/device.env"
fi

# RFC 5737 TEST-NET-1,仅用于文档/示例,不是真实地址
TV_ADDR="${TV_ADDR:-192.0.2.11:5555}"
PICO_ADDR="${PICO_ADDR:-192.0.2.29:5555}"

# 纯 IP(去掉端口)
TV_IP="${TV_ADDR%%:*}"
PICO_IP="${PICO_ADDR%%:*}"

# 本仓库默认的 SDK 布局;可用环境变量覆盖
ANDROID_SDK_DIR="${ANDROID_SDK_DIR:-${ANDROID_HOME:-/opt/android-sdk}}"
export ANDROID_HOME="${ANDROID_HOME:-$ANDROID_SDK_DIR}"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
case ":$PATH:" in
  *":$ANDROID_HOME/platform-tools:"*) ;;
  *) export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$PATH" ;;
esac

# Windows 侧 adb(只用于给 Pico 做 USB 引导)
WINADB="${WINADB:-$_TOOLS_DIR/platform-tools/adb.exe}"
WINADB_PORT="${WINADB_PORT:-15037}"

# 未创建 device.env 时给个提示,不阻断(用户可能想用 -s 手动指定)
if [ ! -f "$_TOOLS_DIR/device.env" ] && [ -z "${EASYANDROID_QUIET:-}" ]; then
  echo "提示: 未找到 tools/device.env,使用示例地址 $TV_ADDR / $PICO_ADDR" >&2
  echo "      复制 tools/device.env.example 并填入真实地址。" >&2
fi

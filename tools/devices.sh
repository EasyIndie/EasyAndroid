#!/usr/bin/env bash
# 连接并列出所有已配置的设备
#
# 用法: bash tools/devices.sh
#
# 设备地址来自 tools/device.env(模板 device.env.example)。
#
# 跨平台:Windows 原生(Git Bash)与 WSL2/Linux 都能跑,
#         平台差异与 adb 解析见 tools/_common.sh 顶部说明。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

if [ -z "$ADB" ]; then
  echo "!! 找不到可用的 adb。看看 tools/README.md 的「前置条件」。" >&2
  exit 1
fi

echo "==> 平台 $PLATFORM  ·  adb $ADB"
# 先 disconnect 再 connect。设备休眠过之后 adb 里常留一条过期记录,
# 这种情况下单发 connect 会被当成"已连接"而直接返回,状态还是不对。
adb_connect_all

printf "%-24s %-10s %s\n" "SERIAL" "STATE" "MODEL"
printf "%-24s %-10s %s\n" "------------------------" "----------" "--------------------"
"$ADB" devices -l 2>/dev/null | awk 'NR>1 && NF {
  m="-"; for (i=3;i<=NF;i++) if ($i ~ /^model:/) { sub(/^model:/,"",$i); m=$i }
  printf "%-24s %-10s %s\n", $1, $2, m
}'

echo
echo "  TV   = $TV_ADDR"
echo "  PICO = $PICO_ADDR"
echo "  指定设备: \"$ADB\" -s <serial> shell ..."

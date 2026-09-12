#!/usr/bin/env bash
# 连接并列出所有已配置的设备
#
# 用法: bash tools/devices.sh
#
# 设备地址来自 tools/device.env(模板 device.env.example)。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

adb start-server >/dev/null 2>&1

for d in "$TV_ADDR" "$PICO_ADDR"; do
  state=$(adb devices | awk -v d="$d" '$1==d{print $2}')
  if [ "$state" != "device" ]; then
    # 先 disconnect 再 connect。设备休眠过之后 adb 里常留一条过期记录,
    # 这种情况下单发 connect 会被当成"已连接"而直接返回,状态还是不对。
    adb disconnect "$d" >/dev/null 2>&1
    adb connect "$d" >/dev/null 2>&1
  fi
done

printf "%-24s %-10s %s\n" "SERIAL" "STATE" "MODEL"
printf "%-24s %-10s %s\n" "------------------------" "----------" "--------------------"
adb devices -l | awk 'NR>1 && NF {
  m="-"; for (i=3;i<=NF;i++) if ($i ~ /^model:/) { sub(/^model:/,"",$i); m=$i }
  printf "%-24s %-10s %s\n", $1, $2, m
}'

echo
echo "  TV   = $TV_ADDR"
echo "  PICO = $PICO_ADDR"
echo "  指定设备: adb -s <serial> shell ..."

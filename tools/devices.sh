#!/usr/bin/env bash
# 连接并列出两台安卓设备 (TCL 电视 / Pico 4)
# 用法: bash tools/devices.sh
export PATH=/opt/android-sdk/platform-tools:$PATH

TV=192.0.2.11:5555
PICO=192.0.2.29:5555

adb start-server >/dev/null 2>&1

for d in "$TV" "$PICO"; do
  state=$(adb devices | awk -v d="$d" '$1==d{print $2}')
  if [ "$state" != "device" ]; then
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
echo "  电视 = 192.0.2.11     Pico = 192.0.2.29"
echo "  指定设备: adb -s <serial> shell ..."

#!/usr/bin/env bash
# 拉一份 Windows 版 platform-tools 到 tools/platform-tools/
#
# 用途只有一个: 通过 USB 给 Pico 开无线调试(见 pico-usb.sh)。
# WSL2 没有 USB 总线,插在 Windows 上的设备只能由 Windows 版 adb 操作。
#
# 产物已 gitignore(20MB+ 的上游二进制,不入库)。
#
# 用法: bash tools/fetch-platform-tools.sh

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DEST="$HERE/platform-tools"
URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

if [ -x "$DEST/adb.exe" ]; then
  echo "已存在: $DEST/adb.exe"
  exit 0
fi

echo "==> 下载 Windows 版 platform-tools"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
curl -# -L -o "$tmp/pt.zip" "$URL"

echo "==> 解压到 $DEST"
# 不用 unzip(很多精简镜像没装),用 python 的 zipfile
python3 -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
  "$tmp/pt.zip" "$HERE"

[ -x "$DEST/adb.exe" ] || { echo "解压后没找到 adb.exe" >&2; exit 1; }
echo "完成: $DEST/adb.exe"
"$DEST/adb.exe" version 2>&1 | tr -d '\r' | head -2

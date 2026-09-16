#!/usr/bin/env bash
# 拉一份 Windows 版 platform-tools 到 tools/platform-tools/
#
# 什么时候需要它
#   · **WSL2**:必需。WSL2 没有 USB 总线,插在 Windows 上的设备只能由
#     Windows 版 adb 操作(pico-usb.sh 的 USB 引导那一步)。
#   · **Windows 原生(Git Bash)**:通常**不需要** —— 你本地跑的 adb 本来就是
#     adb.exe,脚本会直接复用它。除非你机器上根本没装 platform-tools。
#   · Linux / macOS:用不上。
#
# 产物已 gitignore(20MB+ 的上游二进制,不入库)。
#
# 用法: bash tools/fetch-platform-tools.sh
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DEST="$_TOOLS_DIR/platform-tools"
URL="https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

if [ -x "$DEST/adb.exe" ]; then
  echo "已存在: $DEST/adb.exe"
  "$DEST/adb.exe" version 2>&1 | tr -d '\r' | head -2
  exit 0
fi

echo "==> 下载 Windows 版 platform-tools"
tmpd="$(mktmpd)"
[ -n "$tmpd" ] || { echo "!! 建不了临时目录($TMP 不可写)" >&2; exit 1; }
trap 'rm -rf "$tmpd"' EXIT

if ! curl -# -L -o "$tmpd/pt.zip" "$URL"; then
  echo "!! 下载失败。网络受限时可手动下载后解压到 $DEST:" >&2
  echo "   $URL" >&2
  exit 1
fi

echo "==> 解压到 $DEST"
# 不用 unzip(很多精简镜像没装),用 python 的 zipfile
if [ -n "$PY" ]; then
  "$PY" -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" \
    "$(pyfile "$tmpd/pt.zip")" "$(pyfile "$_TOOLS_DIR")"
else
  echo "!! 需要 python3 来解压(或用系统 unzip 手动解到 $DEST)" >&2
  exit 1
fi

[ -x "$DEST/adb.exe" ] || { echo "!! 解压后没找到 adb.exe" >&2; exit 1; }

# Git Bash 下 .exe 的执行位依赖挂载选项;不放心就显式补一下
chmod +x "$DEST/adb.exe" 2>/dev/null || true

echo "完成: $DEST/adb.exe"
"$DEST/adb.exe" version 2>&1 | tr -d '\r' | head -2

#!/usr/bin/env bash
#
# 一条命令验证整套工具链是否还能用
#
# 什么时候跑
#   · 换了机器 / 重装系统
#   · 升级了 JDK / Android SDK / Gradle
#   · 有一阵子没动这个仓库,想确认还能跑通
#
# 做什么
#   环境 → 构建 → Pico(装/起/自截图)→ 电视(装/起/自截图)→ 汇总
#
# 用法
#   bash tools/verify-all.sh                # 全跑
#   bash tools/verify-all.sh --build-only   # 只验环境 + 构建(不需要设备)
#
# 设备不在线会自动跳过并标 SKIP,不算失败 —— 这样在没有真机的环境
# (比如 CI)也能跑。
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

BUILD_ONLY=0
[ "${1:-}" = "--build-only" ] && BUILD_ONLY=1

REPO="$(cd "$_TOOLS_DIR/.." && pwd)"
APP_DIR="$REPO/apps/DualDemo"
PKG="com.example.dualdemo"

PASS=0; FAIL=0; SKIP=0
RESULTS=()
ok(){   RESULTS+=("PASS  $1"); PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad(){  RESULTS+=("FAIL  $1"); FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
skip(){ RESULTS+=("SKIP  $1"); SKIP=$((SKIP+1)); printf '  ⏭️  %s\n' "$1"; }

online(){ adb devices 2>/dev/null | awk -v d="$1" '$1==d && $2=="device"' | grep -q .; }

echo "════════════════ 1/4 环境 ════════════════"
step_env(){
  if command -v java >/dev/null && java -version 2>&1 | grep -q '"17'; then
    ok "JDK 17 ($(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/'))"
  else
    bad "JDK 17 不可用(AGP 8.x 硬性要求)"
  fi
  [ -d "$ANDROID_HOME/platform-tools" ] \
    && ok "Android SDK platform-tools ($ANDROID_HOME)" \
    || bad "找不到 $ANDROID_HOME/platform-tools"
  [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] \
    && ok "cmdline-tools" || bad "cmdline-tools 缺失"
  ls "$ANDROID_HOME"/build-tools/*/aapt2 >/dev/null 2>&1 \
    && ok "build-tools + aapt2" || bad "build-tools 缺失"
  [ -x "$APP_DIR/gradlew" ] && ok "gradlew" || bad "找不到 $APP_DIR/gradlew"
  command -v python3 >/dev/null && ok "python3(脚本用来解析 UI 树)" || bad "python3 缺失"
  [ -f "$_TOOLS_DIR/device.env" ] \
    && ok "tools/device.env" \
    || skip "tools/device.env 未创建(设备地址会用示例值)"
  adb start-server >/dev/null 2>&1
  adb devices >/dev/null 2>&1 && ok "adb 可用" || bad "adb 不可用"
}
step_env

echo
echo "════════════════ 2/4 构建 ════════════════"
step_build(){
  ( cd "$APP_DIR" && ./gradlew assembleDebug --no-daemon --console=plain --max-workers=2 ) \
    > /tmp/verify-build.log 2>&1
  if [ $? -eq 0 ]; then
    ok "assembleDebug"
  else
    bad "assembleDebug(日志: /tmp/verify-build.log)"
    tail -20 /tmp/verify-build.log | sed 's/^/       /'
    return 1
  fi
  local apk="$APP_DIR/app/build/outputs/apk/debug/app-debug.apk"
  [ -f "$apk" ] && ok "APK 产出 ($(stat -c%s "$apk") bytes)" || bad "APK 没产出"

  # debug 包里必须有自截图钩子,release 包里必须没有
  local bt; bt="$(ls -d "$ANDROID_HOME"/build-tools/*/ 2>/dev/null | head -1)"
  if [ -n "$bt" ] && [ -x "${bt}aapt2" ]; then
    local n
    n="$("${bt}aapt2" dump xmltree --file AndroidManifest.xml "$apk" 2>/dev/null | grep -c UiDumpReceiver)"
    [ "$n" -ge 1 ] && ok "debug 包含自截图钩子" || bad "debug 包里没有自截图钩子"
  else
    skip "aapt2 校验钩子"
  fi
}
step_build

if [ "$BUILD_ONLY" = 1 ]; then
  echo
  echo "(--build-only,跳过设备环节)"
else

echo
echo "════════════════ 3/4 Pico(快速迭代目标)════════════════"
step_pico(){
  if ! online "$PICO_ADDR"; then
    skip "Pico 不在线($PICO_ADDR)—— 重启后跑 tools/pico-usb.sh"
    return
  fi
  if timeout 240 adb -s "$PICO_ADDR" install -r -t \
       "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" </dev/null 2>&1 | grep -q Success; then
    ok "Pico 安装"
  else
    bad "Pico 安装"; return
  fi
  # 必须 --launch:装完应用不在前台,DebugHooks 拿不到 Activity,截不到图
  if bash "$_TOOLS_DIR/ui-dump.sh" "$PKG" "$PICO_ADDR" /tmp/verify-pico.png --launch >/tmp/verify-pico.log 2>&1; then
    ok "Pico 启动 + 自截图 ($(grep -oE '[0-9]+x[0-9]+' /tmp/verify-pico.log | tail -1))"
  else
    bad "Pico 自截图(日志: /tmp/verify-pico.log)"
    tail -6 /tmp/verify-pico.log | sed 's/^/       /'
  fi
}
step_pico

echo
echo "════════════════ 4/4 电视(验收目标)════════════════"
step_tv(){
  if ! online "$TV_ADDR"; then
    skip "电视不在线($TV_ADDR)"
    return
  fi
  if bash "$_TOOLS_DIR/tv-install.sh" \
       "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" \
       --shot-out /tmp/verify-tv.png >/tmp/verify-tv.log 2>&1; then
    ok "电视 安装 + 启动 + 自截图 ($(grep -oE '[0-9]+x[0-9]+' /tmp/verify-tv.log | tail -1))"
  else
    bad "电视安装链路(日志: /tmp/verify-tv.log)"
    grep -E '!!|失败' /tmp/verify-tv.log | head -4 | sed 's/^/       /'
  fi
}
step_tv

fi

echo
echo "════════════════ 汇总 ════════════════"
for r in "${RESULTS[@]}"; do
  case "$r" in
    PASS*) printf '  ✅ %s\n' "${r#PASS  }" ;;
    FAIL*) printf '  ❌ %s\n' "${r#FAIL  }" ;;
    SKIP*) printf '  ⏭️  %s\n' "${r#SKIP  }" ;;
  esac
done
echo
printf '  通过 %d  失败 %d  跳过 %d\n' "$PASS" "$FAIL" "$SKIP"
echo
if [ "$FAIL" -gt 0 ]; then
  echo "有问题先查 docs/01(环境)和 docs/05(踩坑速查)。"
  exit 1
fi
echo "工具链正常。"

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

REPO="$_REPO_DIR"
APP_DIR="$REPO/apps/DualDemo"
PKG="com.example.dualdemo"

PASS=0; FAIL=0; SKIP=0; WARN=0
RESULTS=()
ok(){   RESULTS+=("PASS  $1"); PASS=$((PASS+1)); printf '  ✅ %s\n' "$1"; }
bad(){  RESULTS+=("FAIL  $1"); FAIL=$((FAIL+1)); printf '  ❌ %s\n' "$1"; }
skip(){ RESULTS+=("SKIP  $1"); SKIP=$((SKIP+1)); printf '  ⏭️  %s\n' "$1"; }

# warn —— 按【警告】记账,不计入失败。用于「本模式用不到、但值得提醒」的项:
# CI 只跑 --build-only,设备相关的 adb / build-tools 不应把构建判死。
warn(){ RESULTS+=("WARN  $1"); WARN=$((WARN+1)); printf '  ⚠️  %s\n' "$1"; }
# need —— 当前模式下的必需项:完整模式当失败,--build-only 当警告。
need(){ if [ "$BUILD_ONLY" = 1 ]; then warn "$1"; else bad "$1"; fi; }

online(){ adb_online "$1"; }

echo "==> 平台 $PLATFORM"
echo
echo "════════════════ 1/4 环境 ════════════════"
step_env(){
  if command -v java >/dev/null && java -version 2>&1 | grep -q '"17'; then
    ok "JDK 17 ($(java -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/'))"
  else
    bad "JDK 17 不可用(AGP 8.x 硬性要求)"
  fi
  [ -d "$ANDROID_HOME/platform-tools" ] \
    && ok "Android SDK platform-tools ($ANDROID_HOME)" \
    || bad "找不到 $ANDROID_HOME/platform-tools(设 ANDROID_HOME 或 ANDROID_SDK_DIR 指过去)"
  [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] \
    || [ -x "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager.bat" ] \
    && ok "cmdline-tools" || bad "cmdline-tools 缺失"
  # build-tools 里可能是 aapt2 或 aapt2.exe。逐个候选判断,不要用带多个
  # glob 参数的 `ls` —— 只要有一个路径不存在,ls 整体就返回非零(CI 上
  # 没有 aapt2.exe,老写法会恒判失败)。
  local _aapt2=""
  for d in "$ANDROID_HOME"/build-tools/*/; do
    for cand in "${d}aapt2" "${d}aapt2.exe"; do
      [ -f "$cand" ] && { _aapt2="$cand"; break 2; }
    done
  done
  if [ -n "$_aapt2" ]; then
    ok "build-tools + aapt2"
  else
    # aapt2 只用来校验 APK 内容(build 段缺它是 skip),不是构建的硬依赖
    need "build-tools 缺失(没有 aapt2 就验不了 APK 里的钩子/版本号)"
  fi
  [ -x "$APP_DIR/gradlew" ] || [ -f "$APP_DIR/gradlew" ] \
    && ok "gradlew" || bad "找不到 $APP_DIR/gradlew"
  [ -n "$PY" ] && ok "$PY(脚本用来解析 UI 树)" || bad "python3 缺失"
  # Android 11+ 上 shell 读不了 /sdcard/Android/data,取图靠 run-as;这里只做存在性提示
  [ -f "$_TOOLS_DIR/device.env" ] \
    && ok "tools/device.env" \
    || skip "tools/device.env 未创建(设备地址会用示例值)"
  # $ADB 来自基座:tools/platform-tools/ 或 PATH。CI 上 SDK 自带的 adb 在 PATH 里,
  # 但工具的探测要求 -x(可执行位),个别环境会给成不可执行 —— 再兜一层 PATH 检查。
  # adb 只有设备环节用得到,--build-only(CI)下缺了不该判负。
  if [ -n "$ADB" ]; then
    ok "adb 可用($ADB)"
  elif command -v adb >/dev/null 2>&1; then
    ok "adb 可用($(command -v adb))"
  else
    need "adb 不可用(设备环节用得到)"
  fi
  ok "临时目录 $TMP"
}
step_env

echo
echo "════════════════ 2/4 构建 ════════════════"
step_build(){
  local log="$TMP/verify-build.log"
  ( cd "$APP_DIR" && ./gradlew assembleDebug --no-daemon --console=plain --max-workers=2 ) \
    > "$log" 2>&1
  if [ $? -eq 0 ]; then
    ok "assembleDebug"
  else
    bad "assembleDebug(日志: $log)"
    tail -20 "$log" | sed 's/^/       /'
    return 1
  fi
  local apk="$APP_DIR/app/build/outputs/apk/debug/app-debug.apk"
  [ -f "$apk" ] && ok "APK 产出 ($(file_size "$apk") bytes)" || bad "APK 没产出"

  # debug 包里必须有自截图钩子,release 包里必须没有
  # 与环境段的探测保持一致:[ -f ] 而非 [ -x ],避免个别环境可执行位缺失时误判
  local aapt2=""
  for d in "$ANDROID_HOME"/build-tools/*/; do
    for cand in "${d}aapt2" "${d}aapt2.exe"; do
      [ -f "$cand" ] && { aapt2="$cand"; break 2; }
    done
  done
  if [ -n "$aapt2" ]; then
    local n
    n="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk" 2>/dev/null | grep -c UiDumpReceiver)"
    [ "$n" -ge 1 ] && ok "debug 包含自截图钩子" || bad "debug 包里没有自截图钩子"
  else
    skip "aapt2 校验钩子"
  fi

  # 版本号唯一来源:装出来的 APK 里的 versionName 必须等于仓库根 version.properties 的 version。
  # 这是把「唯一来源」变成可执行约束的一步 —— 光靠约定早晚会漂回去。
  local vf="$REPO/version.properties" want got
  want="$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$vf" 2>/dev/null | tr -d '\r' | head -1)"
  if [ -z "$want" ]; then
    bad "读不到 $(basename "$vf") 里的 version=(版本号唯一来源,见 docs/06)"
  elif [ -n "$aapt2" ]; then
    got="$("$aapt2" dump badging "$apk" 2>/dev/null \
          | sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p" | head -1)"
    [ "$got" = "$want" ] \
      && ok "版本号与 version.properties 一致 ($want)" \
      || bad "版本号不一致:APK=$got  version.properties=$want"
  else
    skip "版本号一致性校验(缺 aapt2)"
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
  local apk="$APP_DIR/app/build/outputs/apk/debug/app-debug.apk"
  if run_timeout 240 "$ADB" -s "$PICO_ADDR" install -r -t "$apk" </dev/null 2>&1 | grep -q Success; then
    ok "Pico 安装"
  else
    bad "Pico 安装"; return
  fi
  # 必须 --launch:装完应用不在前台,DebugHooks 拿不到 Activity,截不到图
  local log="$TMP/verify-pico.log" png="$TMP/verify-pico.png"
  if bash "$_TOOLS_DIR/ui-dump.sh" "$PKG" "$PICO_ADDR" "$png" --launch >"$log" 2>&1; then
    ok "Pico 启动 + 自截图 ($(grep -oE '[0-9]+x[0-9]+' "$log" | tail -1))"
  else
    bad "Pico 自截图(日志: $log)"
    tail -6 "$log" | sed 's/^/       /'
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
  local log="$TMP/verify-tv.log"
  if bash "$_TOOLS_DIR/tv-install.sh" \
       "$APP_DIR/app/build/outputs/apk/debug/app-debug.apk" \
       --shot-out "$TMP/verify-tv.png" >"$log" 2>&1; then
    ok "电视 安装 + 启动 + 自截图 ($(grep -oE '[0-9]+x[0-9]+' "$log" | tail -1))"
  else
    bad "电视安装链路(日志: $log)"
    grep -E '!!|失败' "$log" | head -4 | sed 's/^/       /'
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
    WARN*) printf '  ⚠️  %s\n' "${r#WARN  }" ;;
    SKIP*) printf '  ⏭️  %s\n' "${r#SKIP  }" ;;
  esac
done
echo
printf '  通过 %d  失败 %d  警告 %d  跳过 %d\n' "$PASS" "$FAIL" "$WARN" "$SKIP"
echo
if [ "$FAIL" -gt 0 ]; then
  echo "有问题先查 docs/01(环境)和 docs/05(踩坑速查)。"
  exit 1
fi
if [ "$WARN" -gt 0 ]; then
  echo "工具链正常(有警告项:当前模式用不到,完整设备验证前请补齐)。"
else
  echo "工具链正常。"
fi

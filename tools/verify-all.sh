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
#   仓库自检(CI 配置)→ 环境 → 构建 → Pico(装/起/自截图)→ 电视(装/起/自截图)→ 汇总
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

# 外部 action → 期望的最低主版本(供下面 0/4 段用)。
# 这几个主版本都跑在 node24 上;停在更旧的主版本就会跑在已被移除的 Node 20 上,
# GitHub 于是每次 CI 都刷一条 warning。**新引入外部 action 时在这里登记。**
_min_action_major(){
  case "$1" in
    actions/checkout)        printf '5' ;;
    actions/setup-java)      printf '5' ;;
    actions/upload-artifact) printf '5' ;;
    *)                       printf '' ;;
  esac
}

echo "==> 平台 $PLATFORM"
echo
echo "════════════════ 0/4 仓库自检(CI 配置)════════════════"
step_repo(){
  # 排在 1/4 之前:它只读几个 yml、零外部依赖、毫秒级 —— 而它一旦坏了,后面所有
  # CI 都是白跑。并且它与 JDK / SDK / 设备全都无关,CI 和本机跑的是同一份判据。
  #
  # 盯的是两件「坏了也不报错」的事:
  #   · action 主版本停在旧 Node 上 —— GitHub 只刷 warning、不挡 CI,最容易积压
  #     (2026-09 实测:三个 action 一起停在 Node 20,一直没人发现);
  #   · runner 写 `-latest` —— 换 OS 是**无声**发生的。本仓库的 verify-all 会查
  #     $ANDROID_HOME 下的工具链,换 OS 等于换构建环境,不该悄悄发生。
  #
  # 只用 grep 做浅校验,YAML 的合法性交给 GitHub 自己报(它一定会报)。
  # ⚠️ 期望值写死是**有意的闸门**:升 action / 升 runner 都得改这两处,
  #    改的时候就是一次显式决策 —— 别改成「自动取最新」,那样闸门就没了。
  local runner_ok='ubuntu-24.04'
  local found=0 f rel

  for f in "$REPO"/.github/workflows/*.yml "$REPO"/.github/workflows/*.yaml; do
    [ -e "$f" ] || continue
    found=1
    rel=".github/workflows/$(basename "$f")"

    if ! grep -qE '^jobs:' "$f"; then
      bad "$rel 里找不到 jobs:"
      continue
    fi

    local issues='' n_act=0 n_run=0 line no val name ver major need
    # 先剥掉行内注释再取值 —— 我们自己的注释里就写着 `ubuntu-latest` 和 `v4`,
    # 不剥会全判成配置错误。
    while IFS= read -r line; do
      no="${line%%:*}"; val="${line#*:}"; val="${val#*runs-on:}"
      val="${val%%#*}"
      val="${val//[[:space:]]/}"; val="${val//\"/}"; val="${val//\'/}"
      n_run=$((n_run+1))
      if [ "$val" != "$runner_ok" ]; then
        issues="${issues}第 $no 行 runs-on = ${val:-<空>},期望 $runner_ok"
        case "$val" in
          *'{{'*)   issues="${issues}(这里是表达式,静态看不了)" ;;
          *latest*) issues="${issues}(-latest 会在换镜像时无声改变构建环境)" ;;
        esac
        issues="${issues}"$'\n'
      fi
    done < <(grep -nE '^[[:space:]]*runs-on:' "$f")

    while IFS= read -r line; do
      no="${line%%:*}"; val="${line#*:}"; val="${val#*uses:}"
      val="${val%%#*}"
      val="${val//[[:space:]]/}"; val="${val//\"/}"; val="${val//\'/}"
      [ -n "$val" ] || continue
      # 本地 action 与容器 action 不涉及 Node 版本,不参与登记
      case "$val" in ./*|docker://*) continue ;; esac
      n_act=$((n_act+1))
      case "$val" in
        *@*) : ;;
        *) issues="${issues}第 $no 行 $val 没写版本 —— 必须 @主版本(如 @v7)"$'\n'; continue ;;
      esac
      name="${val%@*}"; ver="${val##*@}"
      need="$(_min_action_major "$name")"
      if [ -z "$need" ]; then
        issues="${issues}第 $no 行出现未登记的 action: $val"$'\n'
        issues="${issues}      （新引入的话请登记进 verify-all.sh 的 _min_action_major,并确认它跑在 node24 上）"$'\n'
        continue
      fi
      major="${ver#v}"; major="${major%%.*}"
      case "$major" in
        ''|*[!0-9]*)
          issues="${issues}第 $no 行 $val 的版本不是主版本号 —— 请写 @v<N>(pin SHA 会让弃用检测失效)"$'\n'
          continue ;;
      esac
      if [ "$major" -lt "$need" ]; then
        issues="${issues}第 $no 行 $val 主版本 < $need,仍跑在旧 Node 上"$'\n'
      fi
    done < <(grep -nE '^[[:space:]]*-?[[:space:]]*uses:' "$f")

    [ "$n_run" -ge 1 ] || issues="${issues}没有任何 runs-on"$'\n'
    [ "$n_act" -ge 1 ] || issues="${issues}没有任何外部 action(至少该有 checkout)"$'\n'

    if [ -z "$issues" ]; then
      ok "$rel(runner=$runner_ok,$n_act 个 action 主版本达标)"
    else
      bad "$rel"
      printf '%s\n' "$issues" | sed '/^$/d; s/^/       /'
    fi
  done

  [ "$found" = 1 ] || bad "找不到 .github/workflows/*.yml"
}
step_repo

echo
echo "════════════════ 1/4 环境 ════════════════"
step_env(){
  # JDK 17:AGP 8.x 的硬性要求。
  #
  # 这里验的是「Gradle 将要用的那个 java」,查找顺序与基座 §7 保持一致:
  # 先 $JAVA_HOME,再退回 PATH。
  # ⚠️ 不能只写 `command -v java`:$JAVA_HOME 才是 Gradle 的首选,而它指向的
  #    JDK 未必同时进了 PATH(Windows 上 JDK 装在 Program Files 下,系统 Path
  #    未必跟着更新)。只查 PATH 会把「装好且能用」的 JDK 误报成没装。
  local _javabin=""
  if [ -n "${JAVA_HOME:-}" ] && [ -x "$JAVA_HOME/bin/java" ]; then
    _javabin="$JAVA_HOME/bin/java"
  elif command -v java >/dev/null 2>&1; then
    _javabin="$(command -v java)"
  fi
  if [ -n "$_javabin" ] && "$_javabin" -version 2>&1 | grep -q '"17'; then
    ok "JDK 17 ($("$_javabin" -version 2>&1 | head -1 | sed 's/.*"\(.*\)".*/\1/'))"
  else
    bad "JDK 17 不可用(AGP 8.x 硬性要求)"
  fi
  [ -d "$ANDROID_HOME/platform-tools" ] \
    && ok "Android SDK platform-tools ($ANDROID_HOME)" \
    || bad "找不到 $ANDROID_HOME/platform-tools(设 ANDROID_HOME 或 ANDROID_SDK_DIR 指过去)"
  # ⚠️ 用 [ -f ] 而不是 [ -x ]:Windows 上 .bat **没有可执行位**(实测 -rw-r--r--,
  #    Git Bash 只给 .exe 打 x 位),而 sdkmanager 在 Windows 上正是 .bat ——
  #    用 -x 会把装好的 cmdline-tools 误报成「缺失」。(同 build-tools 那条。)
  # 顺带把原来的 `A || B && ok || bad` 换成显式 if:那种写法依赖左结合的
  # 优先级(等价于 `(A || B) && ok || bad`),读的人要停下来算一遍才知道对不对。
  if [ -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager" ] \
     || [ -f "$ANDROID_HOME/cmdline-tools/latest/bin/sdkmanager.bat" ]; then
    ok "cmdline-tools"
  else
    bad "cmdline-tools 缺失"
  fi
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

echo "════════════════ 1.5/4 签名凭据卫生 ════════════════"
step_signing(){
  # 凭据在不在(不在是正常的 —— 不做发版的人不需要。在的话才往下查)
  if [ ! -f "$_REPO_DIR/keystore.properties" ] && [ ! -f "$_REPO_DIR/tools/keystore/release.jks" ]; then
    skip "本机没有签名凭据(只做开发的话正常)"
    return 0
  fi
  ok "本机有签名凭据"

  # 指纹对不对得上仓里记录的期望值
  if [ -f "$_REPO_DIR/signing-manifest.txt" ]; then
    if bash "$_REPO_DIR/tools/gen-keystore.sh" --manifest >"$TMP/verify-signing.log" 2>&1; then
      ok "指纹与 signing-manifest.txt 一致"
    elif grep -q '❌' "$TMP/verify-signing.log"; then
      bad "指纹与签名期望值**不一致** —— 别用它发版"
      grep -E '❌|期望 |本机 ' "$TMP/verify-signing.log" | sed 's/^/       /'
    else
      # 脚本**自己没跑起来**(缺 JDK / keytool 不在 PATH 等)。这跟「指纹不一致」
      # 是两件完全不同的事,不能混报 —— 说成不一致会让人去导入一份本来没错的
      # 凭据,或者白白换掉本机这把(而换错签名等于让老用户没法升级)。
      # 判据:真的不一致时 cmd_manifest 一定会打出 ❌ 行;没有 ❌ 就是没跑成。
      warn "签名指纹**没能核对**(gen-keystore.sh 没正常执行)"
      sed -n '1,3p' "$TMP/verify-signing.log" | sed 's/^/       /'
    fi
  else
    warn "没有 signing-manifest.txt,无法核对指纹(--manifest --write 生成)"
  fi

  # 工作目录里有没有游离的密钥副本 —— 会漏的主要是「临时目录」和「忘了删的导出」。
  # 实测踩过:--push-secret 每跑一次就在 .tmp/ 漏一份完整凭据包,没人知道。
  if bash "$_REPO_DIR/tools/gen-keystore.sh" --scan >"$TMP/verify-scan.log" 2>&1; then
    ok "没有游离的密钥副本"
  elif grep -qE '额外副本|没被 gitignore' "$TMP/verify-scan.log"; then
    bad "工作目录里有游离的密钥副本:"
    grep -E '额外副本|没被 gitignore' "$TMP/verify-scan.log" | sed 's/^/       /'
  else
    warn "密钥副本扫描**没能运行**(gen-keystore.sh 没正常执行)"
    sed -n '1,3p' "$TMP/verify-scan.log" | sed 's/^/       /'
  fi
}
step_signing


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
  # ⚠️ aapt2(.exe) 是**原生程序**,不认 Git Bash 的 POSIX 路径 —— 它要读的
  #    APK 路径必须先过 win_of。否则 aapt2 找不到文件、往 stderr 报错后退出,
  #    而 stdout 是空的:下面「钩子 / 版本号」两条会**一起误报**。实测 2026-09-18:
  #    构建明明成功、APK 就在那儿,却同时报「没有自截图钩子」和「版本号不一致:APK=」。
  #    (同类坑见 AGENTS.md 的「原生程序路径必须显式转换」。)
  local apk_win
  apk_win="$(win_of "$apk")"
  if [ -n "$aapt2" ]; then
    local n
    n="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk_win" 2>/dev/null | grep -c UiDumpReceiver)"
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
    # 取 versionName —— 用基座的 badging_field。
    # ⚠️ 别写回 `sed -n "s/^package:.*versionName='\([^']*\)'.*/\1/p"`:表达式里那对
    #    单引号会穿过 MSYS2 的参数还原(`'` 被当成引号、参数被重新分词),sed 报
    #    `unterminated `s' command`,取值变空 —— 于是误报「版本号不一致:APK=」。
    #    详见 _common.sh 里 badging_field 的说明。
    local badging
    badging="$("$aapt2" dump badging "$apk_win" 2>/dev/null)"
    got="$(badging_field "$badging" "package:" versionName)"
    [ "$got" = "$want" ] \
      && ok "版本号与 version.properties 一致 ($want)" \
      || bad "版本号不一致:APK=${got:-<取不到>}  version.properties=$want"
  else
    skip "版本号一致性校验(缺 aapt2)"
  fi

  # CHANGELOG.md 的最新条目必须就是当前版本 ——
  # release.sh 同时写这两个文件,所以它们**不该**漂移。这条是防回归。
  if [ -n "$want" ] && [ -f "$_REPO_DIR/CHANGELOG.md" ]; then
    cle_top="$(grep -m1 '^## \[' "$_REPO_DIR/CHANGELOG.md" 2>/dev/null | sed 's/^## \[//;s/\].*//;s/(.*//')"
    [ "$cle_top" = "$want" ] \
      && ok "CHANGELOG 最新条目与版本号一致 ($want)" \
      || bad "CHANGELOG 最新条目是 $cle_top,版本号是 $want(release.sh 应该同时更新它们)"
  elif [ ! -f "$_REPO_DIR/CHANGELOG.md" ]; then
    warn "没有 CHANGELOG.md(生成:bash tools/release.sh --backfill)"
  fi

  # 取签名证书指纹的能力 —— 发版说明里的「签名证书 SHA-256」靠它。
  # 实测踩过:GitHub runner 上的 apksigner 取不到(本机 34.0.0 正常),
  # 于是发布说明里那个代码块**是空的**,而没人发现 —— 一个给用户核对
  # 「是不是同一个应用」的字段空着,比没有更误导。
  # 这条检查让工具链漂移在**每次推送**就暴露,而不是等到发版。
  if [ -n "$aapt2" ]; then
    if fp="$(apk_cert_fp "$apk" 2>/dev/null)" && [ -n "$fp" ]; then
      ok "签名工具链能取到证书指纹 (${fp:0:16}…)"
    else
      bad "取不到 APK 的证书指纹 —— 发版说明里那一节会是空的"
      echo "       apksigner 原始输出:" >&2
      apk_cert_dump "$apk" 2>&1 | sed 's/^/         /' >&2
    fi
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
  # ⚠️ adb.exe 是原生程序,不认 /e/... 形式(与 §6「本机侧路径必须显式转换」同理)。
  #    漏掉这一步时 adb 只会回一句 `failed to stat ...: No such file or directory`,
  #    而下面若只 grep Success,失败原因就被吞掉了 —— 看起来像「设备装不上」。
  local apk_arg out
  apk_arg="$(win_of "$apk")"
  out="$(run_timeout 240 "$ADB" -s "$PICO_ADDR" install -r -t "$apk_arg" </dev/null 2>&1)"
  if printf '%s' "$out" | grep -q Success; then
    ok "Pico 安装"
  else
    bad "Pico 安装"
    printf '%s\n' "$out" | grep -vE '^[[:space:]]*$' | tail -3 | sed 's/^/       /'
    # 最常见的一种:设备上那个包是【别的环境】构建的 debug 包。
    # debug.keystore 每台机器各生成一份,换机器/换 WSL↔Windows 就会撞签名。
    if printf '%s' "$out" | grep -q UPDATE_INCOMPATIBLE; then
      echo "       → 签名不一致(设备上那个包是别的环境构建的),先卸载再装:" >&2
      echo "         $ADB -s $PICO_ADDR uninstall $PKG" >&2
    fi
    return
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

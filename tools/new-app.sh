#!/usr/bin/env bash
# 在 apps/ 下新建一个独立的 Android 工程
#
# 约定见 docs/06-app-conventions.md:
#   apps/ 下每个子目录都是一个独立 Gradle 构建,工程之间不共享代码。
#
# 用法:
#   bash tools/new-app.sh <AppName> <package.id>
#   bash tools/new-app.sh MyPlayer com.example.myplayer
set -euo pipefail

# 载入公共逻辑(平台探测 / SDK 解析 / re_escape / PY 等)。
# ⚠️ 必须**早于**任何用到这些变量的代码 —— 后面替换包名那段就要用 $PY。
# ⚠️ 用 BASH_SOURCE 而不是 $0 —— 被 `source` 加载时 $0 是调用方的名字,
#    会解析出错误的仓库路径。
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/_common.sh"

REPO="$_REPO_DIR"
TEMPLATE="$REPO/apps/DualDemo"
TEMPLATE_PKG="com.example.dualdemo"

NAME="${1:-}"
PKG="${2:-}"

usage() {
  cat >&2 <<'EOF'
用法: bash tools/new-app.sh <AppName> <package.id>

  AppName     大驼峰,作为目录名与 rootProject.name,如 MyPlayer
  package.id  反域名,作为 namespace / applicationId,如 com.example.myplayer

例:
  bash tools/new-app.sh MyPlayer com.example.myplayer
EOF
  exit 2
}

[ -n "$NAME" ] && [ -n "$PKG" ] || usage

# ---- 校验 ----
case "$NAME" in
  [A-Z]*) ;;
  *) echo "AppName 要以大写字母开头(大驼峰): $NAME" >&2; usage ;;
esac
case "$NAME" in
  *[!A-Za-z0-9]*) echo "AppName 只能含字母数字: $NAME" >&2; usage ;;
esac
case "$PKG" in
  *[!a-z0-9._]*|.*|*.) echo "package.id 只能含小写字母/数字/点,且不能以点开头结尾: $PKG" >&2; usage ;;
esac
case "$PKG" in
  *.*) ;;
  *) echo "package.id 至少要有一个点,如 com.example.myplayer" >&2; usage ;;
esac

[ -d "$TEMPLATE" ] || { echo "模板工程不存在: $TEMPLATE" >&2; exit 1; }

DEST="$REPO/apps/$NAME"
[ -e "$DEST" ] && { echo "目标已存在: $DEST" >&2; exit 1; }

# 检查 applicationId 是否与已有工程冲突(装到同一台设备会互相覆盖)
if grep -rqs "applicationId = \"$PKG\"" "$REPO/apps"; then
  echo "applicationId 已被其它工程占用: $PKG" >&2
  grep -rn "applicationId = \"$PKG\"" "$REPO/apps" >&2
  exit 1
fi

echo "==> 从模板复制: apps/DualDemo → apps/$NAME"
cp -r "$TEMPLATE" "$DEST"

# 清掉不该带过来的东西
rm -rf "$DEST/app/build" "$DEST/build" "$DEST/.gradle" "$DEST/.kotlin" \
       "$DEST/local.properties" "$DEST/README.md"
find "$DEST" -name '*.orig' -delete 2>/dev/null || true

echo "==> 替换包名: $TEMPLATE_PKG → $PKG"
# ⚠️ 不要用 sed 做这件事。包名里的 `.` 会被当成正则通配符:
#   · 匹配侧需要转义,但 sed 替换串里的 `&` 又代表「整个匹配」,
#     两边的转义规则不同 —— 仓库里曾因此把 com.example.dualdemo
#     替换成 com&example&dualdemo。
# 换成 python 的 str.replace,是**纯字面量**替换,没有歧义。
FILES="$(grep -rl "$TEMPLATE_PKG" "$DEST" 2>/dev/null || true)"
if [ -z "$FILES" ]; then
  echo "   (没有文件包含模板包名,跳过)"
elif [ -n "$PY" ]; then
  # ⚠️ Windows 原生 python 不认 Git Bash 的 /e/... 路径,列表里的每个路径
  #    都要过 pyfile 转成 Windows 形式,否则 FileNotFoundError。
  printf '%s\n' "$FILES" | while read -r f; do printf '%s\n' "$(pyfile "$f")"; done \
    | "$PY" -c '
import sys
old, new = sys.argv[1], sys.argv[2]
for line in sys.stdin:
    p = line.rstrip("\n")
    if not p: continue
    try:
        s = open(p, encoding="utf-8").read()
    except (UnicodeDecodeError, OSError):
        continue          # gradle-wrapper.jar / PNG 等二进制文件,跳过
    if old in s:
        open(p, "w", encoding="utf-8").write(s.replace(old, new))
        print("   ", p)
' "$TEMPLATE_PKG" "$PKG"
else
  # 没有 python 时退回 sed,但两边分别按各自规则转义
  old_pat="$(re_escape "$TEMPLATE_PKG")"       # 匹配侧
  new_rep="$(printf '%s' "$PKG" | sed 's/[\\&|]/\\&/g')"   # 替换侧:只转义 \ & 和分隔符
  printf '%s\n' "$FILES" | while read -r f; do
    case "$f" in
      *.kt|*.kts|*.xml|*.java|*.pro) sed -i "s|$old_pat|$new_rep|g" "$f" ;;
    esac
  done
fi

echo "==> 调整源码目录结构"
# 注意要覆盖所有 source set,不只是 src/main —— 模板的 debug 钩子在 src/debug/java 下
OLD_REL="$(printf '%s' "$TEMPLATE_PKG" | tr '.' '/')"
NEW_REL="$(printf '%s' "$PKG" | tr '.' '/')"
for SRCROOT in "$DEST"/app/src/*/java; do
  [ -d "$SRCROOT/$OLD_REL" ] || continue
  mkdir -p "$(dirname "$SRCROOT/$NEW_REL")"
  mv "$SRCROOT/$OLD_REL" "$SRCROOT/$NEW_REL"
  find "$SRCROOT" -mindepth 1 -type d -empty -delete
  echo "    ${SRCROOT#"$DEST"/} : $OLD_REL -> $NEW_REL"
done

echo "==> 设置 rootProject.name = $NAME"
sed -i "s|^rootProject.name = .*|rootProject.name = \"$NAME\"|" "$DEST/settings.gradle.kts"

echo "==> 设置应用显示名"
sed -i "s|<string name=\"app_name\">.*</string>|<string name=\"app_name\">$NAME</string>|" \
  "$DEST/app/src/main/res/values/strings.xml"

# ---- local.properties(机器相关,gitignore)----
# (_common.sh 已在文件顶部加载)

# Gradle 需要的是**本机路径**:
#   · Windows 上必须写成 `C:\Users\x\AppData\Local\Android\Sdk` 或 `C:/...`,
#     不能是 Git Bash 的 /c/Users/... —— Gradle 认不出来。
#   · 而且反斜杠在 .properties 里是转义符,统一用正斜杠最稳。
sdk_prop=""
if [ -d "$ANDROID_HOME" ]; then
  if [ "$IS_WINDOWS" = 1 ]; then
    sdk_prop="$(win_of "$ANDROID_HOME" 2>/dev/null || printf '%s' "$ANDROID_HOME")"
    sdk_prop="$(printf '%s' "$sdk_prop" | tr '\\' '/')"
  else
    sdk_prop="$ANDROID_HOME"
  fi
fi

if [ -n "$sdk_prop" ]; then
  printf 'sdk.dir=%s\n' "$sdk_prop" > "$DEST/local.properties"
  echo "==> 写入 local.properties: sdk.dir=$sdk_prop"
else
  echo "!! 没找到 Android SDK,跳过 local.properties。" >&2
  echo "   构建前请设 ANDROID_HOME,或手工在 $DEST/local.properties 里写 sdk.dir=" >&2
fi

# Windows 的 drvfs/NTFS 上 chmod 是空操作,报错忽略即可。
# 真正保证可执行位的是 git 的 --chmod=+x(见 docs/05)。
chmod +x "$DEST/gradlew" 2>/dev/null || true

# ---- README 骨架 ----
cat > "$DEST/README.md" <<EOF
# $NAME

<!-- 一句话说明这个应用做什么 -->

| | |
|---|---|
| 包名 | \`$PKG\` |
| 目标设备 | <!-- 电视 / Pico / 都要 --> |
| minSdk / targetSdk | 29 / 34 |
| 版本号 | 仓库根 \`version.properties\`(唯一来源,见 [docs/06](../../docs/06-app-conventions.md#版本号)) |

## 构建

\`\`\`bash
cd apps/$NAME
./gradlew assembleDebug
# → app/build/outputs/apk/debug/app-debug.apk
\`\`\`

## 安装

\`\`\`bash
# TCL 电视(必须走这个,原因见 docs/03)
bash ../../tools/tv-install.sh app/build/outputs/apk/debug/app-debug.apk

# 其他设备
adb -s "\$PICO_ADDR" install -r app/build/outputs/apk/debug/app-debug.apk
\`\`\`

## 验收

\`\`\`bash
bash ../../tools/device-status.sh "\$TV_ADDR" $PKG
\`\`\`

## 已知限制

<!-- 记下目标设备上的限制,例如 Pico 上截屏不可用 -->
EOF

echo
echo "完成: apps/$NAME"
echo
echo "接下来:"
echo "  1. 编辑 apps/$NAME/README.md(做什么 / 目标设备 / 已知限制)"
echo "  2. 写业务代码: apps/$NAME/app/src/main/java/$(printf '%s' "$PKG" | tr '.' '/')/"
echo "  3. 构建自检: cd apps/$NAME && ./gradlew assembleDebug"
echo "  4. 改版本号只改仓库根的 version.properties(工程里不要写版本字面量)"

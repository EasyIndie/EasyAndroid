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

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"
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
# 点号在正则是通配符,转义一下
esc() { printf '%s' "$1" | sed 's/[.[\*^$]/\\&/g'; }
OLD_RE="$(esc "$TEMPLATE_PKG")"
grep -rl "$TEMPLATE_PKG" "$DEST" 2>/dev/null | while read -r f; do
  case "$f" in
    *.kt|*.kts|*.xml|*.java|*.pro) sed -i "s/$OLD_RE/$(esc "$PKG")/g" "$f" ;;
  esac
done

echo "==> 调整源码目录结构"
OLD_DIR="$DEST/app/src/main/java/$(printf '%s' "$TEMPLATE_PKG" | tr '.' '/')"
NEW_DIR="$DEST/app/src/main/java/$(printf '%s' "$PKG" | tr '.' '/')"
if [ -d "$OLD_DIR" ]; then
  mkdir -p "$(dirname "$NEW_DIR")"
  mv "$OLD_DIR" "$NEW_DIR"
  find "$DEST/app/src/main/java" -mindepth 1 -type d -empty -delete
fi

echo "==> 设置 rootProject.name = $NAME"
sed -i "s|^rootProject.name = .*|rootProject.name = \"$NAME\"|" "$DEST/settings.gradle.kts"

echo "==> 设置应用显示名"
sed -i "s|<string name=\"app_name\">.*</string>|<string name=\"app_name\">$NAME</string>|" \
  "$DEST/app/src/main/res/values/strings.xml"

# ---- local.properties(机器相关,gitignore)----
# shellcheck disable=SC1091
. "$HERE/_common.sh"
if [ -n "${ANDROID_HOME:-}" ]; then
  printf 'sdk.dir=%s\n' "$ANDROID_HOME" > "$DEST/local.properties"
  echo "==> 写入 local.properties: sdk.dir=$ANDROID_HOME"
fi

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

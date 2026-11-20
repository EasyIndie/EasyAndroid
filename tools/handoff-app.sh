#!/usr/bin/env bash
#
# 把一个孵化中的应用交付到它自己的仓库(或先导出到目录)
#
# 仓库定位:`apps/` 是**孵化区** —— 应用在这里创建、跑通、验收,然后交给业务仓库迭代。
# 本脚本负责「交付」这一段里**能机械做对**的部分,并把做不了的说清楚。
#
# 用法
#   bash tools/handoff-app.sh <App> --check                 # 只审计,不改任何东西
#   bash tools/handoff-app.sh <App> --out <dir>             # 导出到目录(先看效果)
#   bash tools/handoff-app.sh <App> --target <repo> --prefix clients/android
#                                                           # 导出进目标仓库的子目录
#
# 交付时会自动生成(这些是客户端/业务仓库必需、孵化区里由仓库根提供的):
#   version.properties      版本号唯一来源(带来源说明)
#   CHANGELOG.md            客户端变更日志骨架
#   signing-manifest.txt    该应用的签名指纹(只放公钥指纹,不是密钥)
#   docs/migration-from-easyandroid.md   来源提交 + 剩余人工项清单
#
# 不会自动做的(脚本会把清单打出来):
#   · CI workflow / tag 命名空间 / secrets
#   · 文档单一来源(API 契约、格式表、品牌)该归到谁
#   · 真机复验
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$HERE/_common.sh"

REPO="$_REPO_DIR"
APP=""; OUT=""; TARGET=""; PREFIX=""; CHECK=0; YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)  CHECK=1 ;;
    --out)    shift; OUT="${1:-}" ;;
    --target) shift; TARGET="${1:-}" ;;
    --prefix) shift; PREFIX="${1:-}" ;;
    --yes|-y) YES=1 ;;
    -h|--help) sed -n '3,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "未知参数: $1" >&2; exit 2 ;;
    *)  if [ -z "$APP" ]; then APP="$1"; else echo "多余参数: $1" >&2; exit 2; fi ;;
  esac
  shift
done

die(){ echo "!! $*" >&2; exit 1; }
ok(){  printf '  ✅ %s\n' "$1"; }
bad(){ printf '  ❌ %s\n' "$1"; }
warn(){ printf '  ⚠️  %s\n' "$1"; }
info(){ printf '     %s\n' "$1"; }

[ -n "$APP" ] || die "用法: bash tools/handoff-app.sh <App> [--check | --out <dir> | --target <repo> --prefix <subdir>]"
SRC="$REPO/apps/$APP"
[ -d "$SRC" ] || die "没有这个孵化工程: apps/$APP"

BLOCK=0; WARNS=0
echo "════════ 审计 apps/$APP ════════"

# ── 1. 可执行位 / 换行 ──────────────────────────────────────────
mode="$(git -C "$REPO" ls-files -s -- "apps/$APP/gradlew" 2>/dev/null | awk '{print $1}')"
if [ "$mode" = "100755" ]; then
  ok "gradlew 在 git 里是可执行的(100755)"
else
  bad "gradlew 在 git 里的 mode 是 ${mode:-<未跟踪>},不是 100755 —— Linux CI 会 Permission denied"
  info "修:git update-index --chmod=+x apps/$APP/gradlew"
  BLOCK=1
fi
crlf=""
for f in gradlew; do
  [ -f "$SRC/$f" ] || continue
  if grep -q $'\r' "$SRC/$f" 2>/dev/null; then crlf="$crlf $f"; fi
done
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q $'\r' "$f" 2>/dev/null && crlf="$crlf ${f#"$SRC"/}"
done < <("$FIND" "$SRC" -name '*.sh' -type f 2>/dev/null)
if [ -n "$crlf" ]; then bad "这些脚本是 CRLF 换行:$crlf"; BLOCK=1; else ok "没有 CRLF 脚本"; fi

# ── 2. 不该带过去的东西 ────────────────────────────────────────
leak="$(git -C "$REPO" ls-files -- "apps/$APP" | grep -E 'local\.properties$|\.jks$|keystore\.properties$|/build/|\.gradle/|\.apk$|\.aab$' || true)"
if [ -n "$leak" ]; then bad "这些文件被跟踪了,不应交付:"; printf '%s\n' "$leak" | sed 's/^/       /'; BLOCK=1
else ok "没有 local.properties / 密钥 / 构建产物被跟踪"; fi

# ── 3. 跨仓引用 ────────────────────────────────────────────────
# 代码里 source 另一个仓库的公共库 = 交付后直接跑不起来,必须挡。
hard_refs="$(git -C "$REPO" grep -n -E 'source[[:space:]]+.*\.\./\.\./tools/|\. \".*\.\./\.\./tools/|/tools/_common\.sh' -- "apps/$APP" 2>/dev/null || true)"
if [ -n "$hard_refs" ]; then
  bad "代码里引用了本的 tools/(交付后会是死路径):"; printf '%s\n' "$hard_refs" | sed 's/^/       /'
  info "改成内联所需的几行(参考 OrzMusic 的 audio-kit/scripts/build-android.sh)"
  BLOCK=1
else
  ok "代码里没有跨仓引用"
fi

# 文档里的相对链接:导出时会自动改写,但先列出来让人知道
doc_refs="$(git -C "$REPO" grep -n -E '\]\(\.\./\.\./(docs|version\.properties|tools)' -- "apps/$APP/README.md" "apps/$APP/docs" 2>/dev/null || true)"
if [ -n "$doc_refs" ]; then
  warn "文档里有指向本仓库的相对链接(导出时会改写成绝对 URL / \$EASYANDROID):"
  printf '%s\n' "$doc_refs" | sed 's/^/       /'
  WARNS=$((WARNS+1))
else
  ok "文档里没有指向本仓库的相对链接"
fi

# ── 4. 版本号从哪来 ────────────────────────────────────────────
rootver="$(sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$REPO/version.properties" | tr -d '\r' | head -1)"
[ -n "$rootver" ] && ok "孵化期版本(继承自仓库根):$rootver" || bad "读不到仓库根 version.properties"

# ── 5. 基本信息 ────────────────────────────────────────────────
pkg="$(grep -m1 'applicationId[[:space:]]*=' "$SRC/app/build.gradle.kts" 2>/dev/null | sed 's/.*"\(.*\)".*/\1/')"
[ -n "$pkg" ] && info "applicationId: $pkg" || warn "读不到 applicationId"

echo
echo "════════ 结论 ════════"
if [ "$BLOCK" = 1 ]; then
  echo "  有硬阻塞,先修好再交付。"
  [ "$CHECK" = 1 ] && exit 1
  exit 1
fi
echo "  可以交付。"
[ "$CHECK" = 1 ] && { echo "  (--check 只审计,没有改任何东西)"; exit 0; }
[ -z "$OUT" ] && [ -z "$TARGET" ] && { echo "  加 --out <dir> 或 --target <repo> --prefix <subdir> 才会真的导出。"; exit 0; }

# ── 目标目录 ───────────────────────────────────────────────────
if [ -n "$TARGET" ]; then
  [ -d "$TARGET/.git" ] || [ -d "$TARGET" ] || die "目标仓库不存在: $TARGET"
  [ -n "$PREFIX" ] || die "--target 需要同时给 --prefix(如 clients/android)"
  DEST="$TARGET/$PREFIX"
else
  DEST="$OUT"
fi
[ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ] && die "目标目录非空: $DEST"

echo
echo "════════ 导出 ════════"
mkdir -p "$DEST"
git -C "$REPO" archive --format=tar "HEAD:apps/$APP" | tar -xf - -C "$DEST" || die "导出失败"
ok "已导出 tracked 文件 → $DEST"

# 文档里的相对链接:改成跨仓能用的形式
python3 - "$DEST" <<'PY' || die "改写文档链接失败"
import os, re, sys
dest = sys.argv[1]
base = 'https://github.com/EasyIndie/EasyAndroid/blob/main'
changed = []
for root, dirs, files in os.walk(dest):
    dirs[:] = [d for d in dirs if d not in ('build', '.gradle', '.kotlin')]
    for f in files:
        if not f.endswith('.md'):
            continue
        p = os.path.join(root, f)
        s = open(p, encoding='utf-8').read()
        o = s
        # 相对链接 → EasyAndroid 的绝对 URL;工具命令 → $EASYANDROID
        s = re.sub(r'\]\(\.\./\.\./docs/([^)]+)\)', r'](%s/docs/\1)' % base, s)
        s = re.sub(r'\]\(\.\./\.\./version\.properties[^)]*\)', '](version.properties)', s)
        s = s.replace('仓库根 `version.properties`', '本目录 `version.properties`')
        # 命令形态先加上引号(路径里有空格时不会断),再处理其它形式
        s = re.sub(r'bash \.\./\.\./tools/([^\s]+)', r'bash "$EASYANDROID/tools/\1"', s)
        s = s.replace('../../tools/', '$EASYANDROID/tools/')
        if '$EASYANDROID' in s and 'EASYANDROID=/path/to/EasyAndroid' not in s:
            note = ('> 设备脚本不在本仓库:`EASYANDROID=/path/to/EasyAndroid` 指向\n'
                    '> [EasyIndie/EasyAndroid](https://github.com/EasyIndie/EasyAndroid)。\n')
            lines = s.split('\n')
            if lines and lines[0].startswith('# '):
                lines.insert(1, '')
                lines.insert(2, note.rstrip('\n'))
                s = '\n'.join(lines)
            else:
                s = note + s
        if s != o:
            open(p, 'w', encoding='utf-8').write(s)
            changed.append(os.path.relpath(p, dest))
print('   改写: ' + (', '.join(changed) if changed else '(无)'))
PY

# ── 生成交付物 ────────────────────────────────────────────────
today="$(date +%F)"
srcsha="$(git -C "$REPO" rev-parse --short HEAD)"

cat > "$DEST/version.properties" <<EOF
# ─────────────────────────────────────────────────────────────
# $APP 版本号 —— 唯一来源
#
# 从 EasyAndroid 的孵化区交付过来,初始版本继承孵化期版本($rootver)。
# 之后版本独立推进,发版由本仓库自己的流程负责。
#
# 推导规则(与 app/build.gradle.kts 一致):
#   versionName = version
#   versionCode = MAJOR*10000 + MINOR*100 + PATCH
#
# 格式:严格 SemVer —— 只允许 MAJOR.MINOR.PATCH,不要带 -beta 这类后缀
# (versionCode 由它推导,后缀会让两个版本撞同一个 code,装不上)。
#
# 版本历史(旧 → 新)
#   $rootver  $today  从 EasyAndroid 孵化区交付(@$srcsha)
# ─────────────────────────────────────────────────────────────
version=$rootver
EOF
ok "version.properties(=$rootver)"

{
  echo "# 更新日志 · $APP"
  echo
  echo "交付前由 EasyAndroid 的孵化区维护,从这里开始由本仓库维护。"
  echo
  echo "格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。"
  echo
  echo "## [$rootver] - $today"
  echo
  echo "### 其他"
  echo
  echo "- 从 EasyAndroid 孵化区交付(\`EasyIndie/EasyAndroid@$srcsha\`)"
} > "$DEST/CHANGELOG.md"
ok "CHANGELOG.md"

# 签名指纹:只搬这个应用的,不带别人的
alias_key="$(sed -n "s/^app\.$APP=//p" "$REPO/signing-manifest.txt" 2>/dev/null | head -1)"
[ -n "$alias_key" ] || alias_key="$(sed -n "s/^alias\.$APP=//p" "$REPO/keystore.properties" 2>/dev/null | head -1)"
fp=""
[ -n "$alias_key" ] && fp="$(sed -n "s/^alias\.$alias_key=//p" "$REPO/signing-manifest.txt" 2>/dev/null | head -1)"
if [ -n "$fp" ]; then
  cat > "$DEST/signing-manifest.txt" <<EOF
# 签名期望值 —— 这个文件**可以**入库,和 keystore.properties 不是一回事。
#
# 里面只有别名和证书 SHA-256 指纹。指纹是公钥的哈希,**不是秘密**。
# 用途:发版前自检「手里这把是不是发布用的那把」;发布流程拿产物指纹与这里比对。
#
# ⚠️ 凭据本体(.jks + 密码)绝对不能入库。指纹格式:小写无冒号(与 apksigner 一致)。
# ⚠️ 已上架后不能换钥匙,也不能改 applicationId —— 都等于换应用。

alias.$APP=$fp
EOF
  ok "signing-manifest.txt(alias.$APP = ${fp:0:16}…)"
else
  warn "EASYANDROID 的 signing-manifest.txt 里没有 $APP 的指纹 —— 交付后要自己补"
  WARNS=$((WARNS+1))
fi

mkdir -p "$DEST/docs"
cat > "$DEST/docs/migration-from-easyandroid.md" <<EOF
# 从 EasyAndroid 孵化区交付

- 来源:\`EasyIndie/EasyAndroid@$srcsha\`(apps/$APP)
- 日期:$today
- 初始版本:$rootver(继承孵化期版本,之后独立推进)

## 已经由脚本处理

- tracked 文件原样导出(不含 local.properties / 密钥 / 构建产物)
- \`version.properties\`:\`findUpward("version.properties")\` 会找到它,构建不用改
- \`CHANGELOG.md\` 骨架、\`signing-manifest.txt\`(仅本应用指纹)
- 文档里指向 EasyAndroid 的链接改成绝对 URL;工具命令改成 \`\$EASYANDROID/tools/...\`

## 还要人工做

- [ ] \`git ls-files -s gradlew\` 仍是 \`100755\`
- [ ] \`./gradlew assembleDebug\` 与 \`testDebugUnitTest\` 在**干净 clone** 能跑
- [ ] CI:PR 门禁 + 独立 tag 线(\`android-v*\`),**不要**给 job 加 \`paths\` 过滤
- [ ] 签名密钥进目标仓库的 secrets;指纹与 \`signing-manifest.txt\` 对齐
- [ ] 文档单一来源:API 契约、格式表、品牌图该归到服务端还是客户端
- [ ] 真机复验(TCL 电视侧载 + Pico 自截图),设备脚本仍用 EasyAndroid 的 \`tools/\`
- [ ] 在 EasyAndroid 里删除孵化工程:\`git rm -r apps/$APP\`
EOF
ok "docs/migration-from-easyandroid.md"

echo
echo "════════ 交付完成 ════════"
echo "  目标: $DEST"
echo "  接下来:"
echo "    1) 人工项见 $DEST/docs/migration-from-easyandroid.md"
echo "    2) 目标仓库里跑一次构建与测试(干净 clone 下)"
echo "    3) 确认无误后在本仓库删除孵化工程: git rm -r apps/$APP"
[ "$WARNS" -gt 0 ] && echo "  ⚠️  有 $WARNS 条提醒,见上面的输出"

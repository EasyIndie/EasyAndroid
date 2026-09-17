#!/usr/bin/env bash
#
# 一条命令发版 —— 版本号从提交信息机械推导,CHANGELOG 自动生成
#
# ── 它解决什么 ──────────────────────────────────────────────────────
# 之前发一版要人工做 5 件事,其中 3 件是**纯记账**:
#
#   1. bash tools/tag-release.sh --bump minor      ← 人工判断段位
#   2. 手工去 version.properties 补「版本历史」注释  ← 记账
#   3. git commit -am "chore(release): x.y.z —— …"  ← 记账
#   4. bash tools/tag-release.sh                    ← 打 tag
#   5. (可选)手写 docs/releases/x.y.z.md            ← 记账
#
# 而「这一版改了什么」被记在**四个地方**:version.properties 的注释块、
# docs/releases/*.md、Release notes、git log —— 四处维护必然漂移。
#
# 现在只要一条命令。段位、CHANGELOG、提交信息全部从提交历史推导:
#
#   bash tools/release.sh
#
# ── 版本号怎么推 ────────────────────────────────────────────────────
# 输入是「上一个 tag..HEAD」的提交信息(必须是 Conventional Commits):
#
#   feat: …                    → MINOR
#   fix: … / perf: …           → PATCH
#   feat!: … / BREAKING CHANGE → MAJOR
#   docs/chore/refactor/test/ci/style/build → 不发版
#
# ⚠️ MAJOR 还是 0 的时候,BREAKING 升 **MINOR** 而不是 MAJOR ——
#    0.x 阶段本来就不承诺稳定,直接跳到 1.0.0 会让人以为已经稳定了。
#    真想到 1.0.0,用 `--version 1.0.0` 明确表达。
#
# 一条 feat/fix 都没有时**不发版**(exit 0),不是错误 —— 只改了文档就不该涨版本。
#
# ── 用法 ────────────────────────────────────────────────────────────
#   bash tools/release.sh                    # 推导 → 写 CHANGELOG → 提交 → 打 tag → 推
#   bash tools/release.sh --dry-run          # 只显示将要发生什么,一个字节都不改
#   bash tools/release.sh --check            # 只校验(提交规范 / 工作区 / 是否已推)
#   bash tools/release.sh --title "…"        # 覆盖自动生成的版本标题
#   bash tools/release.sh --version 1.0.0    # 指定版本,不推导
#   bash tools/release.sh --as minor         # 强制段位(推导不准时的逃生门)
#   bash tools/release.sh --no-verify        # 跳过构建自检(已跑过 verify-all 时)
#   bash tools/release.sh --yes              # 不交互确认(CI / 脚本里用)
#   bash tools/release.sh --check-commits [<range>]   # 只校验提交信息规范(CI 用)
#   bash tools/release.sh --backfill         # 从所有 tag 重建 CHANGELOG.md
#
# 之后 CI 会接手:从 tag 构建签名包 → 建 Release → 挂附件
# (.github/workflows/release.yml)。见 docs/06-app-conventions.md#发布正式版-apk
#
set -uo pipefail

# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

REPO="$_REPO_DIR"
VF="$REPO/version.properties"
CLE="$REPO/CHANGELOG.md"
SLUG="$(repo_slug "$REPO")"

DRY=0; CHECK=0; BACKFILL=0; NOVERIFY=0; YES=0
AS=""; WANTVER=""; TITLE=""; CMRANGE=""; CM=0

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run)       DRY=1 ;;
    --check)         CHECK=1 ;;
    --backfill)      BACKFILL=1 ;;
    --no-verify)     NOVERIFY=1 ;;
    --yes|-y)        YES=1 ;;
    --as)            shift; AS="${1:-}" ;;
    --version)       shift; WANTVER="${1:-}" ;;
    --title)         shift; TITLE="${1:-}" ;;
    --check-commits) shift; CM=1; CMRANGE="${1:-}"; [ "${1:-}" = "" ] || shift; continue ;;
    -h|--help)       sed -n '3,50p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)               echo "未知参数: $1(看 --help)" >&2; exit 2 ;;
  esac
  shift
done

die(){ echo "!! $*" >&2; exit 1; }
ok(){  printf '  ✅ %s\n' "$1"; }
bad(){ printf '  ❌ %s\n' "$1"; }
inf(){ printf '     %s\n' "$1"; }

# 临时目录用**列表**跟踪 —— 覆盖式地写单个变量会漏:
# 后来者把 TMPD 指向新目录,先前那个就再也没人删了。
# (这个坑在 gen-keystore.sh 里已经踩过一次,那边留下了明文私钥。)
# ⚠️ 不能用 `d="$(tmp_new)"` 取路径 —— 命令替换开子 shell,
#    在子 shell 里追加 TMPDIRS 对父 shell 不可见,trap 会遍历空列表。
TMPDIRS=""
TMPD=""
tmp_new(){
  local d; d="$(mktmpd)" || return 1
  TMPDIRS="$TMPDIRS $d"
  TMPD="$d"
}
trap 'for _d in $TMPDIRS; do rm -rf "$_d"; done' EXIT INT TERM HUP

SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
semver_ok(){ [[ "$1" =~ $SEMVER_RE ]]; }
read_version(){ sed -n 's/^version[[:space:]]*=[[:space:]]*//p' "$VF" 2>/dev/null | tr -d '\r' | head -1; }

[ -n "$PY" ] || die "找不到 python3 —— 解析提交信息要用它(见 docs/01)"

git -C "$REPO" rev-parse -q --verify HEAD >/dev/null || die "不是 git 仓库?"

# ══════════════════════════════════════════════════════════════════════
# 提交解析器 —— 一次读一段 git log,产出三样东西:
#   changelog-entry.md  这一版的 CHANGELOG 条目
#   history.txt         version.properties「版本历史」的注释行
#   verdict.txt         推导结果:段位<TAB>新版本<TAB>标题
#
# 用 python 而不是 bash:要处理 scope、`!`、正文里的 BREAKING CHANGE、
# 以及分组排序。bash 正则做这件事会很难读,也难测。
# ══════════════════════════════════════════════════════════════════════
tmp_new || die "建不了临时目录($TMP 不可写)"
mkdir -p "$TMPD"
GEN_PY="$TMPD/gen.py"

cat > "$GEN_PY" <<'PYEOF'
import os, re, sys, datetime

outdir, prev, known, forced_bump, forced_ver, title_override, slug, today = sys.argv[1:9]
raw = sys.stdin.buffer.read().decode('utf-8', 'replace')

# 记录分隔 \x1e,字段分隔 \x1f —— 提交正文里不可能出现这两个控制字符
# 允许 `a+b` 表示一次提交同时属于多类(历史里真有 `docs+fix:` 这种)。
# 段位取其中**最高**的那一类:不兼容 > feat > fix/perf > 其他。
HEAD_RE = re.compile(
    r'^(?P<types>[A-Za-z]+(?:\+[A-Za-z]+)*)(?:\((?P<scope>[^)]*)\))?(?P<bang>!)?:\s*(?P<desc>.+)$')

GROUPS = [
    ('breaking', '⚠️ 不兼容变更'),
    ('feat',     '新增'),
    ('fix',      '修复'),
    ('other',    '其他'),
]
# 不发版的类型:纯记账。列出来是为了让「为什么没发版」可解释。
NOBUMP = {'docs', 'chore', 'refactor', 'test', 'style', 'ci', 'build'}

commits = []
for rec in raw.split('\x1e'):
    rec = rec.strip('\n')
    if not rec:
        continue
    parts = rec.split('\x1f')
    if len(parts) < 3:
        continue
    sha, subject, body = parts[0].strip(), parts[1].strip(), parts[2]
    subject = subject.strip()
    m = HEAD_RE.match(subject)
    if not m:
        commits.append({'sha': sha, 'subject': subject, 'kind': 'unparsed',
                        'type': '', 'types': [], 'scope': '', 'desc': subject, 'breaking': False})
        continue
    types = [t.lower() for t in m.group('types').split('+')]
    typ = types[0]
    scope = (m.group('scope') or '').strip()
    breaking = bool(m.group('bang')) or ('BREAKING CHANGE' in body.upper())
    if breaking:                      kind = 'breaking'
    elif 'feat' in types:             kind = 'feat'
    elif 'fix' in types or 'perf' in types: kind = 'fix'
    else:                             kind = 'other'
    commits.append({'sha': sha, 'subject': subject, 'kind': kind, 'type': typ,
                    'types': types, 'scope': scope, 'desc': m.group('desc').strip(),
                    'breaking': breaking})

# chore(release) 是发版本身的记账提交,不该出现在 CHANGELOG 里
visible = [c for c in commits
           if not ('chore' in c.get('types', [c['type']]) and c['scope'] == 'release')]
unparsed = [c for c in commits if c['kind'] == 'unparsed']

# ── 推导段位 ──
if forced_ver:
    newver, bump = forced_ver, 'forced'
    if not re.match(r'^\d+\.\d+\.\d+$', newver):
        print('BADVER', file=sys.stderr); sys.exit(3)
elif known:
    newver, bump = known, 'known'
elif forced_bump:
    bump = forced_bump
else:
    has_breaking = any(c['kind'] == 'breaking' for c in commits)
    has_feat = any(c['kind'] == 'feat' for c in commits)
    has_fix = any(c['kind'] == 'fix' for c in commits)
    if has_breaking:
        bump = 'minor' if prev.startswith('0.') else 'major'
    elif has_feat:
        bump = 'minor'
    elif has_fix:
        bump = 'patch'
    else:
        bump = 'none'

if not known and not forced_ver:
    try:
        ma, mi, pa = (int(x) for x in prev.split('.'))
    except ValueError:
        print('BADPREV', file=sys.stderr); sys.exit(4)
    if bump == 'major':   ma, mi, pa = ma + 1, 0, 0
    elif bump == 'minor': mi, pa = mi + 1, 0
    elif bump == 'patch': pa += 1
    newver = f'{ma}.{mi}.{pa}' if bump != 'none' else prev

# ── CHANGELOG 条目 ──
def fmt(c):
    scope = f"**{c['scope']}**: " if c['scope'] else ''
    desc = c['desc']
    if slug and c['sha']:
        return f"- {scope}{desc} ([{c['sha']}](https://github.com/{slug}/commit/{c['sha']}))"
    return f"- {scope}{desc}"

lines = []
if slug and prev and newver and prev != newver:
    lines.append(f"## [{newver}](https://github.com/{slug}/compare/{prev}...{newver}) - {today}")
else:
    lines.append(f"## [{newver}] - {today}")
lines.append('')

# 标题:优先 --title;否则取最重要的那条变更的描述
if title_override:
    title = title_override
else:
    pick = None
    for kind in ('breaking', 'feat', 'fix'):
        cand = [c for c in visible if c['kind'] == kind]
        if cand:
            pick = cand[0]
            break
    if pick is None and visible:
        pick = visible[0]
    title = pick['desc'] if pick else '(无用户可见变更)'
    # 提交标题里常有「主标题 —— 补充说明」;取主标题就够,否则拼进
    # `chore(release): x.y.z —— <title>` 会出现两个同级破折号,读着别扭。
    # 想用完整那句就 --title 显式指定。
    title = title.split(' —— ')[0].split('——')[0].strip() or title

for key, heading in GROUPS:
    group = [c for c in visible if c['kind'] == key]
    if not group:
        continue
    lines.append(f'### {heading}')
    lines.append('')
    for c in group:
        lines.append(fmt(c))
    lines.append('')

entry = '\n'.join(lines).rstrip() + '\n'

# ── version.properties 的历史行 ──
hist = [f'#   {newver}  {title}  (git tag {newver})']
if bump == 'major':
    hist.append('#           BREAKING -> MAJOR')
elif bump == 'minor':
    hist.append('#           feat -> MINOR' if not any(c['kind'] == 'breaking' for c in commits)
                else '#           BREAKING -> 0.x 阶段用 MINOR(想上 1.0.0 要 --version 明确指定)')
elif bump == 'patch':
    hist.append('#           fix -> PATCH')
elif bump == 'none':
    hist.append('#           (没有需要发版的变更)')
elif bump == 'known':
    hist.append('#           (按 tag 回填 CHANGELOG)')

os.makedirs(outdir, exist_ok=True)
open(os.path.join(outdir, 'changelog-entry.md'), 'w', encoding='utf-8').write(entry)
open(os.path.join(outdir, 'history.txt'), 'w', encoding='utf-8').write('\n'.join(hist) + '\n')
with open(os.path.join(outdir, 'verdict.txt'), 'w', encoding='utf-8') as f:
    f.write(f'{bump}\t{newver}\t{title}\n')
    for c in commits:
        f.write(f'#\t{c["kind"]}\t{c["subject"]}\n')
if unparsed:
    with open(os.path.join(outdir, 'unparsed.txt'), 'w', encoding='utf-8') as f:
        for c in unparsed:
            f.write(c['subject'] + '\n')
PYEOF
[ -f "$GEN_PY" ] || die "写不出解析器到 $GEN_PY"

# 让 python 拿到一段 commit 区间,产出到 $2
gen_range(){
  local range="$1" out="$2" prev="$3" known="$4" dt="${5:-}"
  [ -n "$dt" ] || dt="$(date '+%Y-%m-%d')"
  mkdir -p "$out"
  git -C "$REPO" log --no-merges --format='%h%x1f%s%x1f%b%x1e' --encoding=UTF-8 "$range" \
    | "$PY" "$(pyfile "$GEN_PY")" "$(pyfile "$out")" "$prev" "$known" "$AS" "$WANTVER" \
        "$TITLE" "$SLUG" "$dt"
}

# ══════════════════════════════════════════════════════════════════════
# 提交信息规范校验(CI 里跑,防止自动化断在「有人写了个不规范的提交」上)
# ══════════════════════════════════════════════════════════════════════
if [ "$CM" = 1 ]; then
  if [ -z "$CMRANGE" ]; then
    last="$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || true)"
    CMRANGE="${last:+$last..}HEAD"
  fi
  # 首次推送时 github.event.before 是全 0
  case "$CMRANGE" in
    0000000*|"") echo "  (没有可校验的区间,跳过)"; exit 0 ;;
  esac
  echo "  校验提交信息规范: $CMRANGE"
  n=0; bad_n=0
  while IFS= read -r subj; do
    [ -n "$subj" ] || continue
    n=$((n+1))
    case "$subj" in
      "Merge "*|"Revert "*|"fixup!"*|"squash!"*|"chore(release):"*) continue ;;
    esac
    if ! printf '%s' "$subj" | grep -qE '^[A-Za-z]+(\+[A-Za-z]+)*(\([^)]*\))?!?: .+'; then
      bad_n=$((bad_n+1)); bad "不符合 Conventional Commits: $subj"
    fi
  done < <(git -C "$REPO" log --no-merges --format=%s "$CMRANGE" 2>/dev/null)
  echo
  if [ "$bad_n" = 0 ]; then
    ok "$n 条提交全部符合规范"
    exit 0
  fi
  echo "  版本号是从提交信息**机械推导**的,不规范的提交会让推导失准。"
  echo "  改成 'type(scope): 描述' 的形式 —— type ∈ feat fix docs chore refactor test ci perf style build"
  exit 1
fi

# ══════════════════════════════════════════════════════════════════════
# --backfill:从所有 tag 重建 CHANGELOG.md
# ══════════════════════════════════════════════════════════════════════
if [ "$BACKFILL" = 1 ]; then
  tmp_new || die "建不了临时目录"
  mapfile -t tags < <(git -C "$REPO" tag --sort=version:refname | grep -E "$SEMVER_RE" || true)
  [ "${#tags[@]}" -gt 0 ] || die "一个版本 tag 都没有"
  out="$TMPD/CHANGELOG.md"
  {
    echo "# 更新日志"
    echo
    echo "本仓库的版本号与变更记录。**这个文件由 \`tools/release.sh\` 生成,不要手改** ——"
    echo "内容来自 Conventional Commits 格式的提交历史。"
    echo
    echo "版本号规则见 [docs/06-app-conventions.md](docs/06-app-conventions.md#版本号);"
    echo "发版流程见 [README.md](README.md#发版)。"
    echo
    echo "格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。"
    echo
  } > "$out"
  # 先按**升序**生成(区间要靠前一个 tag 才算得出来),
  # 再按**降序**拼接 —— 最新版本在最上面,和 release.sh 插入新条目时的位置一致。
  # 踩过:先前直接把升序结果拼上去,导致 --backfill 的 CHANGELOG 最新版在**最下面**,
  #       而发版时又插到最上面,两种顺序混在一起,verify-all 的防漂移检查直接报错。
  prev=""
  for t in "${tags[@]}"; do
    range="${prev:+$prev..}$t"
    o="$TMPD/one-$t"
    # ⚠️ 历史条目要用 **tag 那天的日期**,不是今天 ——
    #    回填时用 `date` 会让所有历史版本都标成同一天。
    tdt="$(git -C "$REPO" log -1 --format=%cd --date=short "$t" 2>/dev/null)"
    gen_range "$range" "$o" "$prev" "$t" "$tdt" || die "生成 $t 的条目失败"
    prev="$t"
  done
  for ((i = ${#tags[@]} - 1; i >= 0; i--)); do
    cat "$TMPD/one-${tags[$i]}/changelog-entry.md" >> "$out"
  done
  cp "$out" "$CLE"
  echo "==> 已重建 $CLE(${#tags[@]} 个版本:${tags[*]})"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════
# 校验:工作区干净 / 分支是 main / 与远端同步
# ══════════════════════════════════════════════════════════════════════
echo "════════ 校验 ════════"
cur="$(read_version)"
semver_ok "$cur" || die "version.properties 的 version='$cur' 不是严格 SemVer"
ok "当前版本 $cur"

br="$(git -C "$REPO" rev-parse --abbrev-ref HEAD)"
[ "$br" = "main" ] && ok "在 main 上" || bad "当前分支是 $br(发版应该在 main 上)"

if [ -n "$(git -C "$REPO" status --porcelain)" ]; then
  bad "工作区不干净 —— 发版提交只能包含版本号和 CHANGELOG"
  inf "先提交或 stash:"
  git -C "$REPO" status --short | sed 's/^/       /'
  [ "$DRY" = 1 ] && { echo; echo "(dry-run:继续往下看推导结果)"; } || exit 1
else
  ok "工作区干净"
fi

if git -C "$REPO" rev-parse -q --verify '@{u}' >/dev/null 2>&1; then
  if [ "$(git -C "$REPO" rev-list --count '@{u}..HEAD')" != 0 ]; then
    bad "有未推送的提交(先 git push —— tag 必须打在已推送的提交上)"
    [ "$DRY" = 1 ] || exit 1
  else
    ok "已与 origin/$br 同步"
  fi
else
  bad "没有上游分支,先在平台上建仓库并 push"
  [ "$DRY" = 1 ] || exit 1
fi

last_tag="$(git -C "$REPO" describe --tags --abbrev=0 2>/dev/null || true)"
[ -n "$last_tag" ] && ok "上一个版本 tag:$last_tag" || inf "还没有任何 tag(这是第一次发版)"
RANGE="${last_tag:+$last_tag..}HEAD"

# 提交信息规范 —— 版本号完全依赖它,所以必须自查
while IFS= read -r subj; do
  [ -n "$subj" ] || continue
  case "$subj" in
    "Merge "*|"Revert "*|"chore(release):"*) continue ;;
  esac
  if ! printf '%s' "$subj" | grep -qE '^[A-Za-z]+(\+[A-Za-z]+)*(\([^)]*\))?!?: .+'; then
    bad "区间内有不符合规范的提交:$subj"
    inf "版本号由提交信息推导,不规范的提交会让它失准。"
    [ "$DRY" = 1 ] || exit 1
  fi
done < <(git -C "$REPO" log --no-merges --format=%s "$RANGE" 2>/dev/null)
ok "提交信息符合 Conventional Commits"

# ══════════════════════════════════════════════════════════════════════
# 推导版本
# ══════════════════════════════════════════════════════════════════════
echo
echo "════════ 推导 ════════"
[ "$AS" != "" ] && info_bump="(强制 --as $AS)" || info_bump=""

tmp_new || die "建不了临时目录"
mkdir -p "$TMPD"

if [ ! -f "$CLE" ]; then
  inf "还没有 CHANGELOG.md —— 先跑一次 --backfill 把历史补上,这次只追加当前版本"
fi

if ! gen_range "$RANGE" "$TMPD" "$last_tag" "" 2>"$TMPD/err.txt"; then
  cat "$TMPD/err.txt" >&2
  die "解析失败"
fi

IFS=$'\t' read -r BUMP NEWVER TITLE_OUT < "$TMPD/verdict.txt"
[ -n "$NEWVER" ] || die "推导不出新版本"

echo "  变更统计(自 $last_tag):"
awk -F'\t' '$1=="#"{n[$2]++} END{
  printf "     feat=%d  fix/perf=%d  不兼容=%d  其他=%d\n",
    n["feat"]+0, n["fix"]+0, n["breaking"]+0, n["other"]+0
}' "$TMPD/verdict.txt"
echo

if [ "$BUMP" = none ]; then
  echo "  ⏭️  自 $last_tag 以来没有 feat / fix / perf / 不兼容变更 —— **不发版**。"
  echo
  echo "     只有文档、重构、测试这类改动时不涨版本号。这是对的:"
  echo "     版本号是给使用者看的「有什么变了」,不是「仓库动过」。"
  echo
  echo "     确实想发(比如要出个带最新文档的包):"
  echo "       bash tools/release.sh --as patch"
  exit 0
fi

echo "  段位      $BUMP"
echo "  新版本    $cur → $NEWVER $info_bump"
echo "  版本标题  $TITLE_OUT"
echo
echo "  CHANGELOG 条目会是:"
sed 's/^/     /' "$TMPD/changelog-entry.md"
echo

if [ "$CHECK" = 1 ]; then
  echo "(--check:校验通过,到这儿结束,没有改任何东西)"
  exit 0
fi

if [ "$DRY" = 1 ]; then
  echo "(--dry-run:上面就是将要发生的事,一个字节都没改)"
  echo
  echo "  还会做:"
  echo "    1. 写 version.properties:version=$NEWVER + 追一行版本历史"
  echo "    2. 把上面那段插到 CHANGELOG.md 顶部"
  echo "    3. git commit -m 'chore(release): $NEWVER —— $TITLE_OUT'"
  echo "    4. git push"
  echo "    5. bash tools/tag-release.sh${NOVERIFY:+ --no-verify}   # 构建自检 + 打 tag + 推"
  echo "    6. CI 接手:从 tag 构建签名包 → 建 Release → 挂附件"
  exit 0
fi

if [ "$YES" != 1 ]; then
  printf '  确认发版 %s?[y/N] ' "$NEWVER"
  read -r ans </dev/tty 2>/dev/null || ans=""
  case "$ans" in [yY]*) ;; *) echo "  已取消,什么都没改。"; exit 0 ;; esac
fi

# ══════════════════════════════════════════════════════════════════════
# 落盘
# ══════════════════════════════════════════════════════════════════════
echo
echo "════════ 写文件 ════════"

vtmp="$(mktmp)" || die "建不了临时文件"
sed "s|^version[[:space:]]*=.*|version=$NEWVER|" "$VF" > "$vtmp" || die "改 version.properties 失败"

# 版本历史:插在**已有历史条目的末尾**(列表本身是旧→新,新的接在后面)
fixed="$(mktmp)" || die "建不了临时文件"
"$PY" - "$(pyfile "$vtmp")" "$(pyfile "$TMPD/history.txt")" "$(pyfile "$fixed")" <<'PYEOF'
import re, sys
vf, hist, out = sys.argv[1:4]
lines = open(vf, encoding='utf-8').read().split('
')
new = open(hist, encoding='utf-8').read().rstrip('
').split('
')

# ⚠️ 插在**已有条目的后面**,不是紧跟在 `# 版本历史` 之后。
#    这个列表是**旧 → 新**排列的(0.0.1 在最上面)。插到最前面会让它变成
#    0.4.0 / 0.0.1 / 0.1.0 …,读起来像列表重新开始了 —— 踩过。
start = None
for i, l in enumerate(lines):
    if re.match(r'^#\s*版本历史\s*$', l):
        start = i
        break
if start is None:
    # 没有这一节就退化成插在 version= 之前,不报错
    j = next((i for i, l in enumerate(lines) if l.startswith('version=')), len(lines))
else:
    # 历史条目 = `#` 后跟 3 个以上空格(含续行),遇到空行或普通注释就结束
    j = start + 1
    while j < len(lines) and re.match(r'^#\s{3,}\S', lines[j]):
        j += 1
lines[j:j] = new
open(out, 'w', encoding='utf-8').write('\n'.join(lines))
PYEOF
mv "$fixed" "$vtmp" || die "插入版本历史失败"
mv "$vtmp" "$VF"
ok "version.properties: version=$NEWVER + 版本历史"

# CHANGELOG:新条目插在最后一个 `## [` 之前(最新在上),保留头部说明
if [ -f "$CLE" ]; then
  ctmp="$(mktmp)" || die "建不了临时文件"
  "$PY" - "$(pyfile "$CLE")" "$(pyfile "$TMPD/changelog-entry.md")" "$(pyfile "$ctmp")" <<'PYEOF'
import sys
cle, entry, out = sys.argv[1:4]
old = open(cle, encoding='utf-8').read()
new = open(entry, encoding='utf-8').read()
idx = old.find('\n## [')
if idx < 0:
    head, rest = old.rstrip() + '\n', ''
else:
    head, rest = old[:idx + 1], old[idx + 1:]
open(out, 'w', encoding='utf-8').write(head + ('\n' if head and not head.endswith('\n\n') else '') + new + '\n' + rest)
PYEOF
  mv "$ctmp" "$CLE"
  ok "CHANGELOG.md:已插入 $NEWVER 条目"
else
  {
    echo "# 更新日志"
    echo
    echo "本仓库的版本号与变更记录。**这个文件由 \`tools/release.sh\` 生成,不要手改** ——"
    echo "内容来自 Conventional Commits 格式的提交历史。"
    echo
    echo "版本号规则见 [docs/06-app-conventions.md](docs/06-app-conventions.md#版本号);"
    echo "发版流程见 [README.md](README.md#发版)。"
    echo
    echo "格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。"
    echo
    cat "$TMPD/changelog-entry.md"
  } > "$CLE"
  ok "CHANGELOG.md:已创建(头部 + $NEWVER)"
fi

# ══════════════════════════════════════════════════════════════════════
# 提交 + 打 tag
# ══════════════════════════════════════════════════════════════════════
echo
echo "════════ 提交并打 tag ════════"
git -C "$REPO" add "$VF" "$CLE" || die "git add 失败"
git -C "$REPO" commit -q -m "chore(release): $NEWVER —— $TITLE_OUT" || die "git commit 失败"
ok "已提交 chore(release): $NEWVER"
git -C "$REPO" push 2>&1 | tail -2 | sed 's/^/     /'
git -C "$REPO" rev-parse -q --verify '@{u}' >/dev/null && \
  [ "$(git -C "$REPO" rev-list --count '@{u}..HEAD')" = 0 ] && ok "已推送" || die "推送后仍有未推提交"

# tag-release.sh 负责「tag 名 == version.properties」这条约束 + 构建自检,不重复实现
tagargs=""
[ "$NOVERIFY" = 1 ] && tagargs="--no-verify"
# shellcheck disable=SC2086
bash "$_TOOLS_DIR/tag-release.sh" $tagargs || die "打 tag 失败(版本号文件已改好并提交,修完可以直接重跑)"

echo
echo "════════ 完成 ════════"
echo "  $cur → $NEWVER"
echo
echo "  CI 会接手:https://github.com/$SLUG/actions"
echo "  产出在这:  https://github.com/$SLUG/releases/tag/$NEWVER"

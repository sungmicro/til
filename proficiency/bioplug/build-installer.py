#!/usr/bin/env python3
"""검증 탭 배포물을 만든다.

verify.html / verify-stats.js / verify-judge.js / verify-app.js 를 원본으로 삼아
두 가지를 생성한다. 원본이 하나뿐이므로 내용이 어긋날 일이 없다.

  install-verify.sh       ~/bioplug 에 설치하는 스크립트 (한 줄 실행)
  verify-standalone.html  JS 를 심어 넣은 단일 파일 (복사 한 번으로 끝)
"""

import hashlib
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
# JS 는 불러오는 순서대로 둔다. verify-app.js 가 앞의 둘에 기댄다.
SCRIPTS = ["verify-stats.js", "verify-judge.js", "verify-app.js"]
SOURCES = ["verify.html"] + SCRIPTS


def read(name):
    return (HERE / name).read_text(encoding="utf-8")


def build_standalone():
    html = read("verify.html")
    tags = "\n".join(f'<script src="{n}"></script>' for n in SCRIPTS)
    if tags not in html:
        raise SystemExit("verify.html 의 script 태그가 예상과 다릅니다. SCRIPTS 순서를 확인하세요.")
    inlined = "\n".join("<script>\n" + read(n) + "</script>" for n in SCRIPTS)
    html = html.replace(tags, inlined)
    html = html.replace(
        "<title>검증 — 비교숙련도 설계</title>",
        "<title>검증 — 비교숙련도 설계</title>\n"
        "<!-- 자동 생성 파일. 고치지 말고 verify.html / verify-*.js 를 고친 뒤"
        " build-installer.py 를 다시 실행할 것. -->",
    )
    return html


def heredoc(name, body):
    """heredoc 은 끝에 줄바꿈을 하나 붙이므로, 원본의 마지막 줄바꿈은 떼고 넣는다.

    이렇게 해야 설치된 파일이 원본과 바이트 단위로 같아진다.
    """
    delim = "VERIFY_EOF_" + name.replace(".", "_").replace("-", "_").upper()
    if delim in body:
        raise SystemExit(f"{name}: 구분자 충돌")
    if not body.endswith("\n"):
        raise SystemExit(f"{name}: 파일이 줄바꿈으로 끝나지 않습니다")
    return f"cat > \"$DEST/{name}\" <<'{delim}'\n{body[:-1]}\n{delim}\n"


def build_installer():
    parts = [
        "#!/usr/bin/env bash",
        "# bio-plug 「검증」 탭 설치 스크립트",
        "#",
        "#   bash install-verify.sh            # ~/bioplug/public 에 설치",
        "#   bash install-verify.sh <경로>      # 다른 위치에 설치",
        "#",
        "# 자동 생성 파일이다. 고치지 말고 build-installer.py 를 다시 실행할 것.",
        "set -euo pipefail",
        "",
        'ROOT="${1:-$HOME/bioplug}"',
        'DEST="$ROOT/public"',
        "",
        'if [ ! -d "$ROOT" ]; then',
        '  echo "오류: $ROOT 가 없습니다. bio-plug 폴더 경로를 인자로 주세요." >&2',
        '  echo "  예: bash install-verify.sh ~/projects/bioplug" >&2',
        "  exit 1",
        "fi",
        'mkdir -p "$DEST"',
        "",
        "# 이미 있으면 덮어쓰기 전에 백업한다.",
        f"for f in {' '.join(SOURCES)}; do",
        '  if [ -f "$DEST/$f" ]; then',
        '    cp "$DEST/$f" "$DEST/$f.bak.$(date +%Y%m%d%H%M%S)"',
        '    echo "기존 파일 백업: $DEST/$f.bak.*"',
        "  fi",
        "done",
        "",
    ]
    for name in SOURCES:
        parts.append(heredoc(name, read(name)))

    parts += [
        'echo ""',
        'echo "설치 완료: $DEST"',
        f"for f in {' '.join(SOURCES)}; do",
        '  printf "  %s (%s bytes)\\n" "$f" "$(wc -c < "$DEST/$f" | tr -d " ")"',
        "done",
        "",
        "# 다시 설치할 수 있도록 스크립트를 프로젝트 안에 둔다.",
        'SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"',
        'KEEP="$ROOT/tools/install-verify.sh"',
        'if [ "$SELF" != "$KEEP" ]; then',
        '  mkdir -p "$ROOT/tools"',
        '  cp "$SELF" "$KEEP"',
        '  echo "재설치용 사본: $KEEP"',
        "fi",
        "",
        "# build.mjs 가 public 을 비우는지 확인해 알려준다.",
        'if [ -f "$ROOT/build.mjs" ] && grep -qE "rm[A-Za-z]*\\(|rimraf|emptyDir" "$ROOT/build.mjs"; then',
        '  echo ""',
        '  echo "주의: build.mjs 가 public 을 지웁니다. 빌드할 때마다 이 파일들이 사라집니다."',
        '  echo "      package.json 의 scripts 에 아래 한 줄을 넣어두면 빌드 후 자동 복구됩니다."',
        "  echo '        \"postbuild\": \"bash tools/install-verify.sh .\"'",
        '  echo "      (빌드 명령이 npm run build 가 아니라면 그 명령 뒤에 직접 이어 붙이세요.)"',
        "fi",
        "",
        'echo ""',
        'echo "확인:  cd $DEST && python3 -m http.server 8000"',
        'echo "       http://localhost:8000/verify.html  (비밀번호 bioplug2026)"',
        'echo ""',
        'echo "배포:  cd $ROOT && node build.mjs && npx vercel --prod --yes"',
        'echo "       https://bioplug.vercel.app/verify"',
        'echo ""',
        'echo "탭 링크는 build.mjs 의 tabsHTML() 이 verify.html 유무를 보고 넣습니다."',
        "",
    ]
    return "\n".join(parts)


def main():
    standalone = build_standalone()
    installer = build_installer()
    (HERE / "verify-standalone.html").write_text(standalone, encoding="utf-8")
    (HERE / "install-verify.sh").write_text(installer, encoding="utf-8")
    (HERE / "install-verify.sh").chmod(0o755)

    for name in ["verify-standalone.html", "install-verify.sh"]:
        data = (HERE / name).read_bytes()
        print(f"{name:26s} {len(data):>7,} bytes  sha256 {hashlib.sha256(data).hexdigest()[:16]}")

    # 심어 넣은 내용이 원본과 같은지 확인한다.
    for src in SCRIPTS:
        if read(src).strip() not in standalone:
            print(f"오류: {src} 가 단일 파일에 제대로 들어가지 않았습니다.", file=sys.stderr)
            return 1
    print("단일 파일에 원본 JS 가 그대로 들어갔습니다.")

    # 설치 스크립트가 원본과 같은 바이트를 써내는지 확인한다.
    installer = (HERE / "install-verify.sh").read_text(encoding="utf-8")
    for name in SOURCES:
        delim = "VERIFY_EOF_" + name.replace(".", "_").replace("-", "_").upper()
        start = installer.index(f"<<'{delim}'\n") + len(f"<<'{delim}'\n")
        end = installer.index(f"\n{delim}\n", start)
        if installer[start:end] + "\n" != read(name):
            print(f"오류: {name} 이 설치본과 다릅니다.", file=sys.stderr)
            return 1
    print("설치 스크립트가 원본과 바이트 단위로 같은 파일을 씁니다.")
    return 0


if __name__ == "__main__":
    sys.exit(main())

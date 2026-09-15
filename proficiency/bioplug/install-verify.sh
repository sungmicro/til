#!/usr/bin/env bash
# bio-plug 「검증」 탭 설치 스크립트
#
#   bash install-verify.sh            # ~/bioplug/public 에 설치
#   bash install-verify.sh <경로>      # 다른 위치에 설치
#
# 자동 생성 파일이다. 고치지 말고 build-installer.py 를 다시 실행할 것.
set -euo pipefail

ROOT="${1:-$HOME/bioplug}"
DEST="$ROOT/public"

if [ ! -d "$ROOT" ]; then
  echo "오류: $ROOT 가 없습니다. bio-plug 폴더 경로를 인자로 주세요." >&2
  echo "  예: bash install-verify.sh ~/projects/bioplug" >&2
  exit 1
fi
mkdir -p "$DEST"

# 이미 있으면 덮어쓰기 전에 백업한다.
for f in verify.html verify-stats.js verify-judge.js verify-app.js; do
  if [ -f "$DEST/$f" ]; then
    cp "$DEST/$f" "$DEST/$f.bak.$(date +%Y%m%d%H%M%S)"
    echo "기존 파일 백업: $DEST/$f.bak.*"
  fi
done

cat > "$DEST/verify.html" <<'VERIFY_EOF_VERIFY_HTML'
<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow">
<title>검증 — 비교숙련도 설계</title>
<style>
  :root {
    --bg: #fbfbf9; --fg: #1c1c1a; --muted: #6b6b63; --line: #e0e0d8;
    --card: #ffffff; --accent: #2f6f4e; --warn: #8a4b1f; --bad: #9b2c2c;
    --chip: #f0f0ea;
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --bg: #16171a; --fg: #e8e8e4; --muted: #9a9a92; --line: #303238;
      --card: #1e2024; --accent: #6fbf90; --warn: #d9a05b; --bad: #e08585;
      --chip: #262930;
    }
  }
  :root[data-theme="dark"] {
    --bg: #16171a; --fg: #e8e8e4; --muted: #9a9a92; --line: #303238;
    --card: #1e2024; --accent: #6fbf90; --warn: #d9a05b; --bad: #e08585;
    --chip: #262930;
  }
  * { box-sizing: border-box; }
  body { background: var(--bg); color: var(--fg); margin: 0;
         font: 15px/1.65 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans KR", sans-serif; }
  .wrap { max-width: 1000px; margin: 0 auto; padding-block: 32px; padding-left: 20px; padding-right: 20px; }
  h1 { font-size: 22px; margin: 0 0 4px; letter-spacing: -0.01em; }
  h2 { font-size: 16px; margin: 32px 0 12px; padding-bottom: 6px; border-bottom: 1px solid var(--line); }
  h3 { font-size: 14px; margin: 20px 0 8px; color: var(--muted); }
  p.sub { color: var(--muted); margin: 0 0 24px; font-size: 13px; }
  .card { background: var(--card); border: 1px solid var(--line); border-radius: 10px; padding: 18px; }
  .grid { display: grid; gap: 14px; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); }
  label { display: block; font-size: 12px; color: var(--muted); margin-bottom: 4px; }
  input, select, textarea, button {
    font: inherit; color: inherit; background: var(--bg);
    border: 1px solid var(--line); border-radius: 6px; padding: 7px 9px; width: 100%;
  }
  textarea { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
  button { background: var(--accent); color: #fff; border: none; cursor: pointer; font-weight: 600; }
  button:hover { filter: brightness(1.08); }
  button.ghost { background: transparent; color: var(--fg); border: 1px solid var(--line); font-weight: 500; }
  .row { display: flex; gap: 10px; flex-wrap: wrap; margin-top: 16px; }
  .row button { width: auto; padding: 9px 18px; }
  .tablewrap { overflow-x: auto; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  th, td { border: 1px solid var(--line); padding: 6px 9px; text-align: left; white-space: nowrap; }
  th { background: var(--chip); font-weight: 600; }
  td.num, th.num { text-align: right; font-variant-numeric: tabular-nums; }
  td input { padding: 4px 6px; min-width: 74px; text-align: right;
             font-variant-numeric: tabular-nums; border-radius: 4px; }
  .note { border-left: 3px solid var(--line); padding: 10px 14px; margin: 14px 0;
          color: var(--muted); font-size: 13px; background: var(--chip); border-radius: 0 6px 6px 0; }
  .note.warn { border-left-color: var(--warn); color: var(--fg); }
  .note.bad  { border-left-color: var(--bad);  color: var(--fg); }
  .ok { color: var(--accent); font-weight: 600; }
  .no { color: var(--bad); font-weight: 600; }
  .wa { color: var(--warn); font-weight: 600; }
  .hidden { display: none !important; }
  #gate { position: fixed; inset: 0; background: var(--bg); display: grid; place-items: center; z-index: 10; }
  #gate .card { width: min(360px, calc(100vw - 40px)); text-align: center; }
  #gateMsg { color: var(--bad); font-size: 13px; min-height: 20px; margin: 8px 0 0; }
  code { background: var(--chip); padding: 1px 5px; border-radius: 4px; font-size: 12.5px; }
  pre { background: var(--chip); border: 1px solid var(--line); border-radius: 8px;
        padding: 14px; overflow-x: auto; font-size: 12px; line-height: 1.5; }
  .spare { color: var(--muted); }
  .excluded { text-decoration: line-through; color: var(--bad); }
  /* 배정표 칸의 둘째 줄 — 그 시편의 스크리닝 값 */
  .cellval { display: block; font-size: 11.5px; font-weight: 400; color: var(--muted); }
  /* 모드 전환 — A 시험 전 설계 / B 시험 후 판정 */
  .modes { display: flex; gap: 6px; margin: 0 0 24px; border-bottom: 1px solid var(--line); }
  .modes button { width: auto; background: transparent; color: var(--muted); font-weight: 500;
                  border: 1px solid transparent; border-bottom: none; border-radius: 8px 8px 0 0;
                  padding: 9px 16px; margin-bottom: -1px; }
  .modes button.on { color: var(--fg); font-weight: 600; background: var(--card);
                     border-color: var(--line); }
  .modes button:hover { filter: none; color: var(--fg); }
  /* 시험자별 입력칸 */
  .boxes { display: grid; gap: 12px; grid-template-columns: repeat(auto-fit, minmax(190px, 1fr)); }
  .box { border: 1px solid var(--line); border-radius: 8px; padding: 10px; background: var(--bg); }
  .box textarea { min-height: 148px; resize: vertical; }
  .box .name { margin-bottom: 6px; font-weight: 600; padding: 5px 7px; }
  .count { font-size: 12px; margin-top: 6px; color: var(--muted);
           font-variant-numeric: tabular-nums; }
  .count.bad { color: var(--bad); font-weight: 600; }
  .count.ok { color: var(--accent); }
</style>
</head>
<body>

<div id="gate">
  <form class="card" id="gateForm">
    <h1>검증</h1>
    <p class="sub">비교숙련도 설계 검증 · 내부용</p>
    <label for="pw">비밀번호</label>
    <input type="password" id="pw" autocomplete="current-password" autofocus>
    <p id="gateMsg" role="alert"></p>
    <div class="row"><button type="submit" style="width:100%">열기</button></div>
  </form>
</div>

<div class="wrap hidden" id="app">
  <h1>검증 — 비교숙련도</h1>
  <p class="sub">시험 전에는 설계를 검증하고, 시험이 끝나면 측정값을 판정한다.</p>

  <div class="modes">
    <button type="button" id="tabA" class="on">A · 시험 전 설계</button>
    <button type="button" id="tabB">B · 시험 후 판정</button>
  </div>

<div id="modeA">
  <p class="sub">
    시험 <strong>전에</strong> 시편을 배정하고, 이 설계로 판정이 성립하는지 확인한다.
    입력하는 값은 본 시험 전 <strong>스크리닝 측정값</strong>이다.
  </p>

  <h2>1. 설계</h2>
  <div class="card">
    <div class="grid">
      <div><label for="nAnalysts">시험자 수</label>
        <select id="nAnalysts"></select></div>
      <div><label for="nSamples">시료 종수</label>
        <select id="nSamples"></select></div>
      <div><label for="reps">시료당 반복 (1인)</label>
        <select id="reps"></select></div>
      <div><label for="spares">여분 (시료당)</label>
        <select id="spares"></select></div>
      <div><label for="unit">입력 단위</label>
        <select id="unit">
          <option value="r">R (항균활성)</option>
          <option value="cfu">CFU (집락수)</option>
        </select></div>
      <div><label for="delta">동등성 한계 δ</label>
        <input type="number" id="delta" value="0.25" step="0.01" min="0.01"></div>
      <div><label for="alpha">유의수준 α</label>
        <input type="number" id="alpha" value="0.05" step="0.01" min="0.001" max="0.2"></div>
      <div><label for="seed">난수 시드</label>
        <input type="number" id="seed" value="20260914" step="1"></div>
    </div>
    <div class="row">
      <button id="btnGrid" type="button">입력표 만들기</button>
      <button id="btnDemo" type="button" class="ghost">예시 값 채우기</button>
    </div>
    <p class="note" id="needNote"></p>
  </div>

  <div id="inputSection" class="hidden">
    <h2>2. 스크리닝 값 입력</h2>
    <div class="card">
      <p class="note">
        각 시편을 본 시험 전에 1회 측정한 값이다. 이 값으로 시료 로트의 균질성을 확인하고,
        통계적 이상치로 판정된 시편만 여분으로 교체한다.
        교체 기준은 Grubbs 검정이며, 결과가 마음에 드는지와는 무관하게 적용된다.
      </p>
      <div class="tablewrap"><table id="inputTable"></table></div>
      <div class="row">
        <button id="btnRun" type="button">검증 및 배정 생성</button>
        <button id="btnClear" type="button" class="ghost">지우기</button>
      </div>
      <p id="inputMsg" class="note bad hidden"></p>
    </div>
  </div>

  <div id="results" class="hidden"></div>
  <div id="rcodeSection" class="hidden">
    <h2>6. 분석 보고서용 R 코드</h2>
    <div class="card">
      <p class="note">
        아래 코드를 <code>proficiency.R</code> 로 저장하고 R 에서 실행하면
        Word 보고서가 만들어진다. 측정이 끝나면 <code>results</code> 의 빈 값을 채우면 된다.
      </p>
      <div class="row">
        <button id="btnCopy" type="button">복사</button>
        <button id="btnDownload" type="button" class="ghost">R 파일 내려받기</button>
        <button id="btnCsv" type="button" class="ghost">배정표 CSV 내려받기</button>
      </div>
      <pre id="rcode"></pre>
    </div>
  </div>
</div><!-- /modeA -->

<div id="modeB" class="hidden">
  <p class="sub">
    시험이 <strong>끝난 뒤</strong> 시험자별 측정값을 넣으면 숙련도를 판정한다.
    R 을 돌리지 않아도 여기서 결과가 나온다.
  </p>

  <h2>1. 조건</h2>
  <div class="card">
    <div class="grid">
      <div><label for="jAnalysts">시험자 수</label>
        <select id="jAnalysts"></select></div>
      <div><label for="jSamples">시료 수</label>
        <select id="jSamples"></select></div>
      <div><label for="jDishes">시료당 페트리 수</label>
        <select id="jDishes"></select></div>
      <div><label for="jUnit">입력 단위</label>
        <select id="jUnit">
          <option value="r">R (항균활성)</option>
          <option value="cfu">CFU (집락수)</option>
        </select></div>
      <div><label for="jDelta">동등성 한계 δ</label>
        <input type="number" id="jDelta" value="0.25" step="0.01" min="0.01"></div>
      <div><label for="jAlpha">유의수준 α</label>
        <input type="number" id="jAlpha" value="0.05" step="0.01" min="0.001" max="0.2"></div>
    </div>
    <p class="note" id="jNeedNote"></p>
  </div>

  <h2>2. 측정값 입력</h2>
  <div class="card">
    <p class="note">
      시험자별로 <strong>숫자만</strong> 붙여넣는다. 엔터로 구분하면 되고 공백·쉼표·탭도 된다.
      엑셀에서 세로로 복사한 것을 그대로 넣을 수 있다.
      칸 안의 순서는 판정에 영향을 주지 않는다 — 한 시험자의 값을 묶어서 보기 때문이다.
    </p>
    <div id="jBoxes" class="boxes"></div>
    <div class="row">
      <button id="jRun" type="button">판정하기</button>
      <button id="jDemo" type="button" class="ghost">예시 값 채우기</button>
      <button id="jClear" type="button" class="ghost">지우기</button>
    </div>
    <p id="jMsg" class="note bad hidden"></p>
  </div>

  <div id="jResults" class="hidden"></div>

  <div id="jReportSection" class="hidden">
    <h2>6. 보고서</h2>
    <div class="card">
      <p class="note">
        판정 결과를 Markdown 으로 옮긴 것이다. 문서에 그대로 붙여넣을 수 있다.
      </p>
      <div class="row">
        <button id="jCopy" type="button">복사</button>
        <button id="jDownload" type="button" class="ghost">Markdown 내려받기</button>
        <button id="jCsv" type="button" class="ghost">측정값 CSV 내려받기</button>
      </div>
      <pre id="jReport"></pre>
    </div>
  </div>
</div><!-- /modeB -->

  <h2>주의</h2>
  <p class="note warn">
    이 페이지의 비밀번호는 브라우저에서만 확인한다. 동료가 실수로 들어오는 것을 막는 용도이며,
    페이지 소스를 보면 우회할 수 있으므로 <strong>실제 접근 통제가 아니다.</strong>
    진짜로 막아야 하는 자료라면 서버 쪽 인증이 필요하다.
  </p>
  <p class="note">
    배정은 시험 <strong>전에</strong> 확정하고 시드와 함께 기록으로 남긴다.
    측정 결과를 보고 배정을 바꾸면 시험자 간 편향을 은폐하게 되고,
    ISO/IEC 17025 기록 요구사항에도 어긋난다.
  </p>
</div>

<script src="verify-stats.js"></script>
<script src="verify-judge.js"></script>
<script src="verify-app.js"></script>
</body>
</html>
VERIFY_EOF_VERIFY_HTML

cat > "$DEST/verify-stats.js" <<'VERIFY_EOF_VERIFY_STATS_JS'
/* 비교숙련도 통계 — 브라우저용 구현 (의존성 없음)
 *
 * proficiency/cfu_stats.py 와 proficiency/R/proficiency.R 의 이식본이다.
 * 세 구현이 같은 값을 내야 하며, tests/test_cross_language.py 가 이를 검사한다.
 */
(function (global) {
  'use strict';

  // --- 분포 함수 -----------------------------------------------------------

  var LG_C = [76.18009172947146, -86.50532032941677, 24.01409824083091,
              -1.231739572450155, 0.1208650973866179e-2, -0.5395239384953e-5];

  function lgamma(x) {
    var y = x, tmp = x + 5.5, ser = 1.000000000190015;
    tmp -= (x + 0.5) * Math.log(tmp);
    for (var j = 0; j < 6; j++) ser += LG_C[j] / ++y;
    return -tmp + Math.log(2.5066282746310005 * ser / x);
  }

  var FPMIN = 1e-300, EPS = 3e-16, MAXIT = 300;

  function betacf(a, b, x) {
    var qab = a + b, qap = a + 1, qam = a - 1;
    var c = 1, d = 1 - qab * x / qap;
    if (Math.abs(d) < FPMIN) d = FPMIN;
    d = 1 / d;
    var h = d;
    for (var m = 1; m <= MAXIT; m++) {
      var m2 = 2 * m;
      var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
      d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
      c = 1 + aa / c;  if (Math.abs(c) < FPMIN) c = FPMIN;
      d = 1 / d; h *= d * c;
      aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
      d = 1 + aa * d; if (Math.abs(d) < FPMIN) d = FPMIN;
      c = 1 + aa / c;  if (Math.abs(c) < FPMIN) c = FPMIN;
      d = 1 / d;
      var del = d * c; h *= del;
      if (Math.abs(del - 1) < EPS) break;
    }
    return h;
  }

  function betainc(a, b, x) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    var lbeta = lgamma(a + b) - lgamma(a) - lgamma(b);
    if (x < (a + 1) / (a + b + 2)) {
      return Math.exp(lbeta + a * Math.log(x) + b * Math.log1p(-x)) * betacf(a, b, x) / a;
    }
    return 1 - Math.exp(lbeta + b * Math.log1p(-x) + a * Math.log(x)) * betacf(b, a, 1 - x) / b;
  }

  function fSf(f, d1, d2) { return f <= 0 ? 1 : betainc(d2 / 2, d1 / 2, d2 / (d2 + d1 * f)); }
  function tSf(t, df) {
    var p = 0.5 * betainc(df / 2, 0.5, df / (df + t * t));
    return t >= 0 ? p : 1 - p;
  }
  function tCdf(t, df) { return 1 - tSf(t, df); }

  function bisect(target, lo, hi, fn) {
    for (var i = 0; i < 200; i++) {
      var mid = (lo + hi) / 2;
      if (fn(mid) < target) lo = mid; else hi = mid;
    }
    return (lo + hi) / 2;
  }
  function tPpf(p, df) { return bisect(p, -1e3, 1e3, function (x) { return tCdf(x, df); }); }
  function fPpf(p, d1, d2) {
    return bisect(p, 0, 1e6, function (x) { return 1 - fSf(x, d1, d2); });
  }

  // --- 기술통계 -------------------------------------------------------------

  function mean(xs) { return xs.reduce(function (a, b) { return a + b; }, 0) / xs.length; }
  function variance(xs) {
    var m = mean(xs);
    return xs.reduce(function (a, x) { return a + (x - m) * (x - m); }, 0) / (xs.length - 1);
  }
  function sd(xs) { return Math.sqrt(variance(xs)); }
  function median(xs) {
    var ys = xs.slice().sort(function (a, b) { return a - b; }), n = ys.length, h = n >> 1;
    return n % 2 ? ys[h] : (ys[h - 1] + ys[h]) / 2;
  }

  // --- 검정 -----------------------------------------------------------------

  function anovaOneway(groups, alpha) {
    alpha = alpha === undefined ? 0.05 : alpha;
    var k = groups.length;
    var all = [].concat.apply([], groups);
    var grand = mean(all), n = all.length;
    var ssB = 0, ssW = 0;
    groups.forEach(function (g) {
      var m = mean(g);
      ssB += g.length * (m - grand) * (m - grand);
      g.forEach(function (x) { ssW += (x - m) * (x - m); });
    });
    var df1 = k - 1, df2 = n - k;
    var msB = ssB / df1, msW = ssW / df2;
    var F = msW === 0 ? (msB > 0 ? Infinity : 0) : msB / msW;
    var p = msW === 0 ? (msB > 0 ? 0 : 1) : fSf(F, df1, df2);
    return { name: '일원배치 분산분석', statistic: F, pValue: p, passed: p > alpha,
             ssB: ssB, ssW: ssW, df1: df1, df2: df2, msB: msB, msW: msW, grand: grand };
  }

  function levene(groups, alpha) {
    var z = groups.map(function (g) {
      var c = median(g);
      return g.map(function (x) { return Math.abs(x - c); });
    });
    var r = anovaOneway(z, alpha);
    return { name: '분산 동질성 검정 (Brown-Forsythe)', statistic: r.statistic,
             pValue: r.pValue, passed: r.passed };
  }

  function grubbs(xs, alpha) {
    alpha = alpha === undefined ? 0.05 : alpha;
    var n = xs.length, m = mean(xs), s = sd(xs);
    if (s === 0) return { statistic: 0, pValue: 1, passed: true, index: -1, value: null, critical: NaN };
    var dev = xs.map(function (x) { return Math.abs(x - m) / s; });
    var g = Math.max.apply(null, dev), idx = dev.indexOf(g);
    var a = g * g * n / ((n - 1) * (n - 1));
    var p = a >= 1 ? 0 : Math.min(1, 2 * n * tSf(Math.sqrt(a * (n - 2) / (1 - a)), n - 2));
    var tc = tPpf(1 - alpha / (2 * n), n - 2);
    var gc = ((n - 1) / Math.sqrt(n)) * Math.sqrt(tc * tc / (n - 2 + tc * tc));
    return { statistic: g, pValue: p, critical: gc, index: idx, value: xs[idx], passed: g <= gc };
  }

  function cochranC(groups, alpha) {
    alpha = alpha === undefined ? 0.05 : alpha;
    var k = groups.length, n = groups[0].length;
    var vars = groups.map(variance);
    var total = vars.reduce(function (a, b) { return a + b; }, 0);
    if (total === 0) return { statistic: 0, pValue: 1, passed: true, index: -1, critical: NaN, variances: vars };
    var c = Math.max.apply(null, vars) / total, idx = vars.indexOf(Math.max.apply(null, vars));
    var nu = n - 1;
    var fc = fPpf(1 - alpha / k, nu, (k - 1) * nu);
    var cc = 1 / (1 + (k - 1) / fc);
    var p = c >= 1 ? 0 : Math.min(1, k * fSf((k - 1) * c / (1 - c), nu, (k - 1) * nu));
    return { statistic: c, pValue: p, critical: cc, index: idx, passed: c <= cc, variances: vars };
  }

  function tostAllPairs(groups, delta, alpha) {
    alpha = alpha === undefined ? 0.05 : alpha;
    var a = anovaOneway(groups, alpha), mse = a.msW, dfe = a.df2;
    var pairs = [], worst = 0;
    for (var i = 0; i < groups.length; i++) {
      for (var j = i + 1; j < groups.length; j++) {
        var diff = mean(groups[i]) - mean(groups[j]);
        var se = Math.sqrt(mse * (1 / groups[i].length + 1 / groups[j].length));
        var p = se === 0 ? (Math.abs(diff) < delta ? 0 : 1)
              : Math.max(tSf((diff + delta) / se, dfe), tCdf((diff - delta) / se, dfe));
        pairs.push({ i: i, j: j, diff: diff, pValue: p });
        if (p > worst) worst = p;
      }
    }
    return { name: '동등성 검정 (TOST)', pairs: pairs, pValue: worst, passed: worst < alpha,
             maxAbsDiff: Math.max.apply(null, pairs.map(function (x) { return Math.abs(x.diff); })),
             delta: delta };
  }

  function algorithmA(xs) {
    var p = xs.length;
    var x = median(xs);
    var s = 1.483 * median(xs.map(function (v) { return Math.abs(v - x); }));
    for (var it = 0; it < 50; it++) {
      if (s === 0) break;
      var d = 1.5 * s;
      var w = xs.map(function (v) { return Math.min(Math.max(v, x - d), x + d); });
      var nx = mean(w);
      var ns = 1.134 * Math.sqrt(w.reduce(function (acc, v) {
        return acc + (v - nx) * (v - nx); }, 0) / (p - 1));
      var done = Math.abs(nx - x) < 1e-10 && Math.abs(ns - s) < 1e-10;
      x = nx; s = ns;
      if (done) break;
    }
    return { mean: x, sd: s };
  }

  function zScores(means, assigned, sigma) {
    var est = algorithmA(means);
    var a = (assigned === undefined || assigned === null) ? est.mean : assigned;
    var g = (sigma === undefined || sigma === null) ? est.sd : sigma;
    return {
      assigned: a, sigma: g,
      scores: means.map(function (v) {
        var z = g === 0 ? NaN : (v - a) / g;
        var flag = isNaN(z) ? '판정불가' : Math.abs(z) < 2 ? '만족'
                 : Math.abs(z) < 3 ? '경고' : '부적합';
        return { value: v, z: z, flag: flag };
      })
    };
  }

  // --- 난수 (시드 고정) ------------------------------------------------------

  function mulberry32(seed) {
    var t = seed >>> 0;
    return function () {
      t += 0x6D2B79F5;
      var r = t;
      r = Math.imul(r ^ (r >>> 15), r | 1);
      r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
      return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
    };
  }
  function shuffled(arr, rnd) {
    var a = arr.slice();
    for (var i = a.length - 1; i > 0; i--) {
      var j = Math.floor(rnd() * (i + 1));
      var t = a[i]; a[i] = a[j]; a[j] = t;
    }
    return a;
  }
  function gauss(rnd, mu, sigma) {
    var u = 1 - rnd(), v = rnd();
    return mu + sigma * Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
  }

  global.ProfStats = {
    lgamma: lgamma, betainc: betainc, fSf: fSf, tSf: tSf, tCdf: tCdf,
    tPpf: tPpf, fPpf: fPpf,
    mean: mean, variance: variance, sd: sd, median: median,
    anovaOneway: anovaOneway, levene: levene, grubbs: grubbs, cochranC: cochranC,
    tostAllPairs: tostAllPairs, algorithmA: algorithmA, zScores: zScores,
    mulberry32: mulberry32, shuffled: shuffled, gauss: gauss
  };
})(typeof window !== 'undefined' ? window : globalThis);
VERIFY_EOF_VERIFY_STATS_JS

cat > "$DEST/verify-judge.js" <<'VERIFY_EOF_VERIFY_JUDGE_JS'
/* 검증 탭 — 모드 B 판정 코어
 *
 * 시험이 끝난 뒤 시험자별 측정값을 받아 ISO/IEC 17043 · ISO 13528 방식으로 판정한다.
 * proficiency/judge.py 와 같은 통계를 같은 순서로 수행하며, 값이 일치하는지는
 * tests/test_judge.mjs 가 judge.py 의 출력과 대조해 검사한다.
 *
 * 화면을 건드리지 않는다. DOM 연결은 verify-app.js 가 한다.
 */
(function (global) {
  'use strict';

  var S = global.ProfStats;

  // 집락수 계수 유효범위. 이 밖의 값은 희석 단계를 다시 봐야 한다.
  var COUNT_MIN = 30, COUNT_MAX = 300;
  var DEFAULT_DELTA = 0.25, DEFAULT_ALPHA = 0.05;
  // judge.py 와 같은 기본값. 100,000 회가 브라우저에서 1초 안에 끝난다.
  var DEFAULT_TRIALS = 100000, DEFAULT_SEED = 20260914;

  // 16진수나 Infinity 같은 것이 Number() 를 통과하므로 십진수 꼴만 받는다.
  var NUM_RE = /^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$/;

  /** 엔터·공백·쉼표·탭으로 구분된 숫자 목록을 읽는다. 숫자가 아닌 토큰은 따로 모은다. */
  function parseNumbers(text) {
    var values = [], invalid = [];
    String(text == null ? '' : text).split(/[\s,;]+/).forEach(function (tok) {
      if (tok === '') return;
      if (NUM_RE.test(tok)) values.push(Number(tok));
      else invalid.push(tok);
    });
    return { values: values, invalid: invalid };
  }

  /** 판정이 성립하는 입력인지 본다. 문제가 없으면 null, 있으면 사람이 읽을 메시지. */
  function validate(groups) {
    if (!groups || groups.length < 2) {
      return '시험자가 2명 이상이어야 비교할 수 있습니다.';
    }
    var sizes = groups.map(function (g) { return g.length; })
      .filter(function (v, i, a) { return a.indexOf(v) === i; })
      .sort(function (a, b) { return a - b; });
    if (sizes.length !== 1) {
      return '시험자마다 측정값 개수가 다릅니다: ' + sizes.join(', ');
    }
    if (sizes[0] < 2) {
      return '시험자당 측정값이 1개뿐이면 시험자 내 변동을 추정할 수 없어 ' +
             '분산분석이 성립하지 않습니다.';
    }
    return null;
  }

  /** 입력 단위에 맞게 변환한다. R 은 이미 log 단위이므로 건드리지 않는다. */
  function prepare(groups, inputType) {
    if (inputType === 'cfu') {
      return {
        groups: groups.map(function (g) {
          return g.map(function (v) { return Math.log10(v); });
        }),
        unit: 'log10(CFU)'
      };
    }
    return {
      groups: groups.map(function (g) { return g.slice(); }),
      unit: 'R (항균활성, log 단위)'
    };
  }

  /** 계수 유효범위를 벗어난 값을 시험자별로 모은다. */
  function countRangeWarnings(rawGroups, names) {
    var out = [];
    rawGroups.forEach(function (g, i) {
      var bad = g.filter(function (v) { return v < COUNT_MIN || v > COUNT_MAX; });
      if (bad.length) out.push({ name: names[i], values: bad });
    });
    return out;
  }

  /** 현행 판정 기준(등분산 + 분산분석)을 통과하는지. */
  function passesClassic(groups, alpha) {
    return S.levene(groups, alpha).passed && S.anovaOneway(groups, alpha).passed;
  }

  /* 값 전체를 무작위로 재배정했을 때 현행 기준을 통과하는 비율.
   *
   * 실제 배정이 이 분포의 어디에 있는지가 진단의 핵심이다. 통과율이 높은데
   * 실제 배정만 탈락한다면, 우연이 아니라 시험자별 체계적 편향이 실재한다는 뜻이다. */
  function randomReallocationRate(groups, trials, seed, alpha) {
    var pool = [].concat.apply([], groups);
    var n = groups[0].length, k = groups.length;
    var rnd = S.mulberry32(seed);
    var hit = 0;
    for (var t = 0; t < trials; t++) {
      var sh = S.shuffled(pool, rnd), gs = [];
      for (var i = 0; i < k; i++) gs.push(sh.slice(i * n, (i + 1) * n));
      if (passesClassic(gs, alpha)) hit++;
    }
    return hit / trials;
  }

  /** 전체 판정. 입력이 성립하지 않으면 예외를 던진다. */
  function analyze(names, rawGroups, opts) {
    opts = opts || {};
    var inputType = opts.inputType || 'r';
    var delta = opts.delta === undefined ? DEFAULT_DELTA : opts.delta;
    var alpha = opts.alpha === undefined ? DEFAULT_ALPHA : opts.alpha;
    var trials = opts.trials === undefined ? DEFAULT_TRIALS : opts.trials;
    var seed = opts.seed === undefined ? DEFAULT_SEED : opts.seed;

    var bad = validate(rawGroups);
    if (bad) throw new Error(bad);
    if (inputType === 'cfu' && rawGroups.some(function (g) {
      return g.some(function (v) { return v <= 0; });
    })) {
      throw new Error('CFU 는 0 이하일 수 없습니다 (log 변환 불가).');
    }

    var prep = prepare(rawGroups, inputType);
    var groups = prep.groups;
    var n = groups[0].length;
    var means = groups.map(S.mean);
    var stdevs = groups.map(S.sd);

    var flat = [].concat.apply([], groups);
    var grubbsAll = S.grubbs(flat, alpha);
    // 같은 값이 여러 번 나올 수 있으므로 검정이 돌려준 인덱스를 그대로 쓴다.
    var owner = names[Math.floor(grubbsAll.index / n)];

    var tost = S.tostAllPairs(groups, delta, alpha);
    var levene = S.levene(groups, alpha);
    var anova = S.anovaOneway(groups, alpha);

    return {
      names: names.slice(),
      unit: prep.unit,
      inputType: inputType,
      alpha: alpha,
      delta: delta,
      nPerAnalyst: n,
      values: groups,
      means: means,
      stdevs: stdevs,
      levene: levene,
      anova: anova,
      // judge.py 는 최대 평균차를 통계량으로 보고한다. 같은 자리에 같은 값을 둔다.
      tost: { name: tost.name, statistic: tost.maxAbsDiff, pValue: tost.pValue,
              passed: tost.passed, pairs: tost.pairs, delta: delta },
      grubbsAll: grubbsAll,
      grubbsAllOwner: owner,
      grubbsMeans: S.grubbs(means, alpha),
      z: S.zScores(means),
      classicPass: levene.passed && anova.passed,
      randomRate: randomReallocationRate(groups, trials, seed, alpha),
      trials: trials,
      seed: seed,
      countWarnings: inputType === 'cfu' ? countRangeWarnings(rawGroups, names) : []
    };
  }

  global.ProfJudge = {
    parseNumbers: parseNumbers,
    validate: validate,
    analyze: analyze,
    COUNT_MIN: COUNT_MIN,
    COUNT_MAX: COUNT_MAX,
    DEFAULT_TRIALS: DEFAULT_TRIALS
  };
})(typeof window !== 'undefined' ? window : globalThis);
VERIFY_EOF_VERIFY_JUDGE_JS

cat > "$DEST/verify-app.js" <<'VERIFY_EOF_VERIFY_APP_JS'
/* 검증 탭 — 화면 로직
 *
 * 하는 일
 *   1. 시험 전 스크리닝 값으로 시료 로트의 균질성을 확인한다 (Cochran)
 *   2. Grubbs 로 이상치 시편을 판정하고 여분으로 교체한다
 *   3. 순환 라틴 구성으로 균형 배정을 만든다
 *   4. 이 설계로 판정이 성립하는지 몬테카를로로 확인한다
 *   5. 분석 보고서용 R 코드를 만든다
 *
 * 하지 않는 일
 *   측정이 끝난 값에 담당자를 맞춰 끼워 p 값을 통과시키는 탐색은 넣지 않는다.
 *   그렇게 통과시키면 실재하는 시험자 간 편향을 은폐하게 되고,
 *   실제 수행자와 다른 담당자가 기재된 기록이 남는다.
 */
(function () {
  'use strict';

  var S = window.ProfStats;
  var $ = function (id) { return document.getElementById(id); };

  // 비밀번호의 SHA-256. 평문은 소스에 두지 않는다.
  // 바꾸려면 브라우저 콘솔에서:
  //   crypto.subtle.digest('SHA-256', new TextEncoder().encode('새비밀번호'))
  //     .then(b => console.log([...new Uint8Array(b)].map(x=>x.toString(16).padStart(2,'0')).join('')))
  var PW_HASH = 'b3f2c34c21cb51f85a48c9f704e736b07ead3d5528a1b3f94acc5777e2d02a78';
  var SESSION_KEY = 'bioplug.verify.unlocked';

  var state = { spec: null, values: null, result: null };

  // --- 잠금 -----------------------------------------------------------------

  function unlock() {
    $('gate').classList.add('hidden');
    $('app').classList.remove('hidden');
  }

  async function sha256Hex(text) {
    var buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
    return Array.from(new Uint8Array(buf))
      .map(function (b) { return b.toString(16).padStart(2, '0'); }).join('');
  }

  $('gateForm').addEventListener('submit', async function (e) {
    e.preventDefault();
    var msg = $('gateMsg');
    if (!crypto || !crypto.subtle) {
      msg.textContent = '이 브라우저에서는 확인할 수 없습니다 (HTTPS 필요).';
      return;
    }
    var hex = await sha256Hex($('pw').value);
    if (hex === PW_HASH) {
      try { sessionStorage.setItem(SESSION_KEY, '1'); } catch (err) { /* 무시 */ }
      unlock();
    } else {
      msg.textContent = '비밀번호가 맞지 않습니다.';
      $('pw').select();
    }
  });

  try { if (sessionStorage.getItem(SESSION_KEY) === '1') unlock(); } catch (e) { /* 무시 */ }

  // --- 입력 -----------------------------------------------------------------

  function fillSelect(id, from, to, def) {
    var el = $(id);
    for (var i = from; i <= to; i++) {
      var o = document.createElement('option');
      o.value = String(i); o.textContent = String(i);
      if (i === def) o.selected = true;
      el.appendChild(o);
    }
  }
  fillSelect('nAnalysts', 2, 12, 5);
  fillSelect('nSamples', 1, 8, 3);
  fillSelect('reps', 1, 6, 2);
  fillSelect('spares', 0, 10, 2);

  function readSpec() {
    var k = +$('nAnalysts').value, ns = +$('nSamples').value;
    var reps = +$('reps').value, spares = +$('spares').value;
    return {
      k: k, ns: ns, reps: reps, spares: spares,
      perSample: k * reps + spares,
      needed: k * reps,
      runs: ns * reps,
      unit: $('unit').value,
      delta: +$('delta').value,
      alpha: +$('alpha').value,
      seed: +$('seed').value,
      analysts: Array.from({ length: k }, function (_, i) { return String.fromCharCode(65 + i); }),
      samples: Array.from({ length: ns }, function (_, i) { return String(i + 1); })
    };
  }

  function updateNeedNote() {
    var s = readSpec();
    $('needNote').innerHTML =
      '시험자 1인이 <strong>' + s.runs + '개</strong>씩 수행 → 배정 시편 <strong>' +
      (s.k * s.runs) + '개</strong>, 여분 <strong>' + (s.spares * s.ns) + '개</strong>. ' +
      '시료마다 <strong>' + s.perSample + '개</strong>(배정 ' + s.needed + ' + 여분 ' + s.spares +
      ')의 스크리닝 값을 입력한다.';
  }
  ['nAnalysts', 'nSamples', 'reps', 'spares'].forEach(function (id) {
    $(id).addEventListener('change', updateNeedNote);
  });
  updateNeedNote();

  function buildGrid() {
    var s = readSpec();
    state.spec = s;
    var t = $('inputTable');
    var head = '<tr><th>시료</th>';
    for (var j = 0; j < s.perSample; j++) {
      head += '<th class="num">' + (j < s.needed ? String(j + 1) : '여' + (j - s.needed + 1)) + '</th>';
    }
    head += '</tr>';
    var body = '';
    for (var i = 0; i < s.ns; i++) {
      body += '<tr><th>' + s.samples[i] + '</th>';
      for (var c = 0; c < s.perSample; c++) {
        body += '<td><input type="number" step="any" data-r="' + i + '" data-c="' + c + '"></td>';
      }
      body += '</tr>';
    }
    t.innerHTML = head + body;
    $('inputSection').classList.remove('hidden');
    $('results').classList.add('hidden');
    $('rcodeSection').classList.add('hidden');

    // 엑셀에서 붙여넣기 지원
    t.addEventListener('paste', onPaste);
  }

  function onPaste(e) {
    var txt = (e.clipboardData || window.clipboardData).getData('text');
    if (!txt || !/[\t\n]/.test(txt)) return;
    e.preventDefault();
    var start = e.target.closest('td');
    if (!start) return;
    var r0 = +start.querySelector('input').dataset.r;
    var c0 = +start.querySelector('input').dataset.c;
    txt.trim().split(/\r?\n/).forEach(function (line, dr) {
      line.split(/\t|,/).forEach(function (cell, dc) {
        var el = document.querySelector(
          'input[data-r="' + (r0 + dr) + '"][data-c="' + (c0 + dc) + '"]');
        if (el) el.value = cell.trim();
      });
    });
  }

  function readValues() {
    var s = state.spec, out = [], missing = 0;
    for (var i = 0; i < s.ns; i++) {
      var row = [];
      for (var c = 0; c < s.perSample; c++) {
        var el = document.querySelector('input[data-r="' + i + '"][data-c="' + c + '"]');
        var v = el.value.trim();
        if (v === '' || isNaN(+v)) { missing++; row.push(null); } else { row.push(+v); }
      }
      out.push(row);
    }
    return { values: out, missing: missing };
  }

  $('btnGrid').addEventListener('click', buildGrid);
  $('btnClear').addEventListener('click', function () {
    document.querySelectorAll('#inputTable input').forEach(function (el) { el.value = ''; });
  });

  $('btnDemo').addEventListener('click', function () {
    buildGrid();
    var s = state.spec;
    var rnd = S.mulberry32(s.seed);
    var cfu = s.unit === 'cfu';
    for (var i = 0; i < s.ns; i++) {
      for (var c = 0; c < s.perSample; c++) {
        var v = cfu ? Math.round(S.gauss(rnd, 180, 35)) : S.gauss(rnd, 0, 0.14);
        var el = document.querySelector('input[data-r="' + i + '"][data-c="' + c + '"]');
        el.value = cfu ? String(Math.max(31, v)) : v.toFixed(2);
      }
    }
  });

  // --- 배정 (순환 라틴 구성) --------------------------------------------------

  function buildOrders(k, samples, reps, rnd) {
    var ns = samples.length;
    var labels = S.shuffled(samples, rnd);
    var offsets = S.shuffled(
      Array.from({ length: k }, function (_, i) { return i % ns; }), rnd);
    var positions = S.shuffled(
      Array.from({ length: ns * reps }, function (_, i) { return i; }), rnd);
    return offsets.map(function (off) {
      return positions.map(function (c) { return labels[(off + c) % ns]; });
    });
  }

  function checkBalance(spec, rows) {
    var issues = [];
    spec.analysts.forEach(function (a) {
      spec.samples.forEach(function (s) {
        var n = rows.filter(function (r) { return r.analyst === a && r.sample === s; }).length;
        if (n !== spec.reps) issues.push(a + ' 의 시료 ' + s + ' 배정이 ' + n + '개 (기대 ' + spec.reps + '개)');
      });
    });
    var ids = rows.map(function (r) { return r.id; });
    if (new Set(ids).size !== ids.length) issues.push('시편 ID 중복 배정');

    var table = [];
    for (var pos = 1; pos <= spec.runs; pos++) {
      var counts = {};
      spec.samples.forEach(function (s) {
        counts[s] = rows.filter(function (r) { return r.order === pos && r.sample === s; }).length;
      });
      table.push(counts);
      var vals = Object.values(counts);
      if (Math.max.apply(null, vals) - Math.min.apply(null, vals) > 1) {
        issues.push('순서 ' + pos + ' 의 시료 분포 편중');
      }
    }
    return { passed: issues.length === 0, issues: issues, table: table };
  }

  // --- 실행 -------------------------------------------------------------------

  function run() {
    var s = state.spec;
    var read = readValues();
    var msg = $('inputMsg');
    if (read.missing > 0) {
      msg.textContent = '비어 있거나 숫자가 아닌 칸이 ' + read.missing + '개 있습니다.';
      msg.classList.remove('hidden');
      return;
    }
    if (s.unit === 'cfu' && read.values.some(function (r) { return r.some(function (v) { return v <= 0; }); })) {
      msg.textContent = 'CFU 는 0 이하일 수 없습니다 (log 변환 불가).';
      msg.classList.remove('hidden');
      return;
    }
    msg.classList.add('hidden');
    state.values = read.values;

    // 단위 변환: R 은 이미 log 이므로 변환하지 않는다.
    var work = s.unit === 'cfu'
      ? read.values.map(function (row) { return row.map(function (v) { return Math.log10(v); }); })
      : read.values.map(function (row) { return row.slice(); });

    // 1) 시편 이상치 판정 (Grubbs, 시료 단위) → 여분으로 교체
    var perSample = work.map(function (row, i) {
      var excluded = [], kept = row.map(function (v, j) { return j; });
      // 이상치가 없을 때까지 반복하되, 여분 개수만큼만 제외할 수 있다.
      for (var pass = 0; pass < s.spares; pass++) {
        var sub = kept.map(function (j) { return row[j]; });
        if (sub.length < 3) break;
        var g = S.grubbs(sub, s.alpha);
        if (g.passed) break;
        var gone = kept[g.index];
        excluded.push({ idx: gone, value: read.values[i][gone], G: g.statistic, crit: g.critical });
        kept = kept.filter(function (j) { return j !== gone; });
      }
      var residual = S.grubbs(kept.map(function (j) { return row[j]; }), s.alpha);
      return { sample: s.samples[i], kept: kept, excluded: excluded, residualOutlier: !residual.passed };
    });

    var shortage = perSample.filter(function (p) { return p.kept.length < s.needed; });

    // 2) 로트 간 균질성 (Cochran) — 채택된 시편만, 개수를 맞춰서
    var cochran = null;
    if (s.ns >= 2 && !shortage.length) {
      var groups = perSample.map(function (p, i) {
        return p.kept.slice(0, s.needed).map(function (j) { return work[i][j]; });
      });
      cochran = S.cochranC(groups, s.alpha);
    }

    // 3) 균형 배정
    var rnd = S.mulberry32(s.seed);
    var orders = buildOrders(s.k, s.samples, s.reps, rnd);
    var pools = {};
    perSample.forEach(function (p, i) {
      pools[p.sample] = S.shuffled(
        p.kept.slice(0, s.needed).map(function (j) {
          return { id: 'S' + p.sample + '-' + String(j + 1).padStart(2, '0'), screen: read.values[i][j] };
        }), rnd);
    });
    var rows = [];
    if (!shortage.length) {
      s.analysts.forEach(function (a, ai) {
        orders[ai].forEach(function (sample, pos) {
          var item = pools[sample].pop();
          rows.push({ analyst: a, order: pos + 1, sample: sample, id: item.id, screen: item.screen });
        });
      });
    }
    var balance = rows.length ? checkBalance(s, rows) : { passed: false, issues: ['시편 부족'], table: [] };

    // 4) 설계 검증 — 스크리닝 산포로 시험자 내 표준편차를 추정한다.
    var pooled = null, design = null, attain = null;
    if (!shortage.length) {
      var ssw = 0, dfw = 0;
      perSample.forEach(function (p, i) {
        var v = p.kept.map(function (j) { return work[i][j]; });
        if (v.length >= 2) { ssw += S.variance(v) * (v.length - 1); dfw += v.length - 1; }
      });
      pooled = dfw > 0 ? Math.sqrt(ssw / dfw) : null;
      if (pooled) {
        design = simulateDesign(s.k, s.runs, pooled, s.delta, s.alpha, 1500, s.seed);
        attain = attainableDelta(s.k, s.runs, pooled, s.alpha, 0.8, 400, s.seed);
      }
    }

    state.result = { spec: s, perSample: perSample, shortage: shortage, cochran: cochran,
                     rows: rows, balance: balance, pooled: pooled, design: design, attain: attain };
    render();
  }

  function simulateDesign(k, reps, sigma, delta, alpha, trials, seed) {
    var rnd = S.mulberry32(seed);
    var c = { anova: 0, tost: 0, z: 0 };
    for (var t = 0; t < trials; t++) {
      var groups = [];
      for (var i = 0; i < k; i++) {
        var g = [];
        for (var j = 0; j < reps; j++) g.push(S.gauss(rnd, 0, sigma));
        groups.push(g);
      }
      if (S.anovaOneway(groups, alpha).passed) c.anova++;
      if (S.tostAllPairs(groups, delta, alpha).passed) c.tost++;
      var z = S.zScores(groups.map(S.mean));
      if (z.scores.every(function (x) { return x.flag === '만족'; })) c.z++;
    }
    return { anova: c.anova / trials, tost: c.tost / trials, z: c.z / trials, sigma: sigma };
  }

  function attainableDelta(k, reps, sigma, alpha, target, trials, seed) {
    for (var i = 0; i <= 30; i++) {
      var d = 0.05 + (3.0 - 0.05) * i / 30;
      if (simulateDesign(k, reps, sigma, d, alpha, trials, seed).tost >= target) {
        return { delta: d, achieved: true };
      }
    }
    return { delta: null, achieved: false };
  }

  $('btnRun').addEventListener('click', run);

  // --- 출력 -------------------------------------------------------------------

  function f(x, d) { return x === null || x === undefined || isNaN(x) ? '-' : x.toFixed(d === undefined ? 4 : d); }
  function pct(x) { return (x * 100).toFixed(1) + '%'; }
  function esc(t) { return String(t).replace(/[&<>]/g, function (c) {
    return { '&': '&amp;', '<': '&lt;', '>': '&gt;' }[c]; }); }

  function render() {
    var r = state.result, s = r.spec, h = [];

    h.push('<h2>3. 시편 스크리닝</h2><div class="card">');
    h.push('<div class="tablewrap"><table><tr><th>시료</th><th class="num">입력</th>' +
           '<th class="num">채택</th><th>제외된 시편 (Grubbs)</th><th>판정</th></tr>');
    r.perSample.forEach(function (p) {
      var ex = p.excluded.length
        ? p.excluded.map(function (e) {
            return '<span class="excluded">' + esc(e.value) + '</span> (G=' + f(e.G, 3) +
                   ' &gt; ' + f(e.crit, 3) + ')'; }).join(', ')
        : '<span class="spare">없음</span>';
      var verdict = p.kept.length < s.needed
        ? '<span class="no">여분 부족</span>'
        : p.residualOutlier ? '<span class="wa">이상치 남음</span>' : '<span class="ok">적합</span>';
      h.push('<tr><th>' + esc(p.sample) + '</th><td class="num">' + (s.perSample) +
             '</td><td class="num">' + p.kept.length + '</td><td>' + ex + '</td><td>' + verdict + '</td></tr>');
    });
    h.push('</table></div>');

    if (r.shortage.length) {
      h.push('<p class="note bad">이상치를 빼고 나니 배정에 필요한 ' + s.needed +
             '개를 채우지 못하는 시료가 있습니다. 여분을 늘리거나, 해당 로트를 다시 만들어야 합니다.</p>');
    }
    if (r.cochran) {
      h.push('<h3>로트 간 균질성 (Cochran C)</h3><p>C = ' + f(r.cochran.statistic) +
             ', 임계값 ' + f(r.cochran.critical) + ' → <strong>' +
             (r.cochran.passed ? '<span class="ok">균질</span>' : '<span class="no">불균질</span>') +
             '</strong></p>');
      if (s.reps * s.k <= 3) {
        h.push('<p class="note">반복수가 적어 균질성 검정의 검정력이 매우 낮습니다. ' +
               '“균질하다”를 주장할 근거로는 약합니다.</p>');
      }
    }
    h.push('</div>');

    if (r.rows.length) {
      h.push('<h2>4. 배정표</h2><div class="card">');
      h.push('<div class="tablewrap"><table><tr><th>시험자</th>');
      for (var i = 1; i <= s.runs; i++) h.push('<th class="num">' + i + '번</th>');
      h.push('</tr>');
      s.analysts.forEach(function (a) {
        h.push('<tr><th>' + esc(a) + '</th>');
        for (var pos = 1; pos <= s.runs; pos++) {
          var row = r.rows.find(function (x) { return x.analyst === a && x.order === pos; });
          // 시편 ID 아래에 그 시편의 스크리닝 값을 같이 둔다. 시험 당일 대조용이다.
          h.push('<td class="num">' + esc(row.id) +
                 '<span class="cellval">' + esc(row.screen) + '</span></td>');
        }
        h.push('</tr>');
      });
      h.push('</table></div>');
      h.push('<p class="spare" style="font-size:13px">칸 아래 작은 숫자는 그 시편의 ' +
             '스크리닝 값 (' + (s.unit === 'cfu' ? 'CFU' : 'R') + ') 입니다. ' +
             '본 시험 측정값이 아니라 배정 전에 잰 값입니다.</p>');
      h.push('<h3>균형 검증</h3><p>완전균형·순서균형: <strong>' +
             (r.balance.passed ? '<span class="ok">적합</span>' : '<span class="no">부적합</span>') +
             '</strong>' + (r.balance.issues.length ? ' — ' + esc(r.balance.issues.join('; ')) : '') + '</p>');
      h.push('<p class="spare" style="font-size:13px">난수 시드 <code>' + s.seed +
             '</code> — 이 값을 기록해두면 배정을 언제든 재현할 수 있습니다.</p></div>');
    }

    if (r.design) {
      var d = r.design;
      h.push('<h2>5. 사전 설계 검증</h2><div class="card">');
      h.push('<p>스크리닝 산포에서 추정한 시험자 내 표준편차 σ<sub>w</sub> = <strong>' +
             f(r.pooled) + '</strong> ' + (s.unit === 'cfu' ? '(log10 CFU)' : '(R, log 단위)') + '</p>');
      h.push('<div class="tablewrap"><table><tr><th>항목</th><th class="num">값</th></tr>');
      h.push('<tr><td>분산분석이 “차이 없음”으로 나올 비율</td><td class="num">' + pct(d.anova) + '</td></tr>');
      h.push('<tr><td><strong>동등성 입증 비율 (δ=±' + s.delta + ')</strong></td><td class="num"><strong>' +
             pct(d.tost) + '</strong></td></tr>');
      h.push('<tr><td>z-score 전원 만족 비율</td><td class="num">' + pct(d.z) + '</td></tr>');
      h.push('</table></div>');
      h.push('<p class="note">시험자 간 편향이 <strong>전혀 없다고 가정</strong>했을 때의 통과율입니다. ' +
             '스크리닝은 한 사람이 측정하므로 σ<sub>w</sub> 추정치에는 시험자 간 성분이 빠져 있고, ' +
             '따라서 실제보다 낙관적입니다.</p>');
      if (d.tost < 0.5) {
        var alt = r.attain && r.attain.achieved
          ? '이 설계로 입증 가능한 한계는 약 <strong>±' + f(r.attain.delta, 2) + '</strong> 입니다.'
          : '반복수를 크게 늘리지 않으면 어떤 한계로도 입증하기 어렵습니다.';
        h.push('<p class="note bad"><strong>경고</strong> 편향이 없어도 동등성 입증률이 ' + pct(d.tost) +
               ' 에 그칩니다. 이 설계로는 “차이가 없다”를 입증할 수 없습니다. ' + alt +
               ' δ 는 통과할 때까지 늘리는 값이 아니라 적합성 목적에 따라 규정하는 값이므로, ' +
               '답은 반복수를 늘리거나 시험 기법을 개선하는 쪽입니다.</p>');
      }
      h.push('</div>');
    }

    $('results').innerHTML = h.join('');
    $('results').classList.remove('hidden');

    if (r.rows.length) {
      $('rcode').textContent = generateR();
      $('rcodeSection').classList.remove('hidden');
    }
  }

  // --- R 코드 생성 -------------------------------------------------------------

  function generateR() {
    var r = state.result, s = r.spec;
    var ids = s.analysts.map(function (a) {
      return r.rows.filter(function (x) { return x.analyst === a; })
        .sort(function (p, q) { return p.order - q.order; })
        .map(function (x) { return '"' + x.id + '"'; }).join(', ');
    });

    return [
'# 비교숙련도 분석 — 자동 생성 코드',
'# 생성일: ' + new Date().toISOString().slice(0, 10) + '   난수 시드: ' + s.seed,
'#',
'# 배정은 시험 전에 확정된 것이다. 측정이 끝나면 results 의 NA 를 채우고 실행한다.',
'# base R 만 사용하므로 추가 패키지 설치 없이 돌아간다.',
'',
'analysts <- c(' + s.analysts.map(function (a) { return '"' + a + '"'; }).join(', ') + ')',
'delta <- ' + s.delta + '   # 동등성 한계 (log 단위)',
'alpha <- ' + s.alpha,
'input_type <- "' + s.unit + '"  # "r" = 항균활성 R(변환 없음), "cfu" = 집락수(log10 변환)',
'',
'# 배정된 시편 ID (행 = 시험자, 열 = 수행 순서)',
'specimens <- rbind(',
ids.map(function (row, i) {
  return '  c(' + row + ')' + (i < ids.length - 1 ? ',' : '');
}).join('\n'),
')',
'rownames(specimens) <- analysts',
'',
'# ── 측정값을 여기에 채운다 (행 = 시험자, 열 = 수행 순서) ──',
'results <- matrix(NA_real_, nrow = ' + s.k + ', ncol = ' + s.runs + ',',
'                  dimnames = list(analysts, NULL))',
s.analysts.map(function (a) {
  return 'results["' + a + '", ] <- c(' +
    Array(s.runs).fill('NA').join(', ') + ')';
}).join('\n'),
'',
'stopifnot(!anyNA(results))  # 값을 다 채우기 전에는 여기서 멈춘다',
'',
'# ── 준비 ──',
'values <- if (input_type == "cfu") log10(results) else results',
'unit_label <- if (input_type == "cfu") "log10(CFU)" else "R (항균활성, log 단위)"',
'long <- data.frame(',
'  analyst = factor(rep(analysts, times = ncol(values)), levels = analysts),',
'  value = as.vector(values))',
'',
'# ── 등분산 검정 (Levene, 중앙값 중심 = Minitab 기본값) ──',
'z <- abs(long$value - ave(long$value, long$analyst, FUN = median))',
'lev <- anova(lm(z ~ long$analyst))',
'',
'# ── 일원 분산분석 ──',
'fit <- anova(lm(value ~ analyst, data = long))',
'mse <- fit[["Mean Sq"]][2]; dfe <- fit[["Df"]][2]',
'',
'# ── 동등성 검정 (TOST, 교집합-합집합) ──',
'pairs <- do.call(rbind, lapply(combn(seq_along(analysts), 2, simplify = FALSE), function(ij) {',
'  a <- values[ij[1], ]; b <- values[ij[2], ]',
'  d <- mean(a) - mean(b)',
'  se <- sqrt(mse * (1/length(a) + 1/length(b)))',
'  p <- max(pt((d + delta)/se, dfe, lower.tail = FALSE), pt((d - delta)/se, dfe))',
'  data.frame(A = analysts[ij[1]], B = analysts[ij[2]], diff = d, p = p)',
'}))',
'',
'# ── 이상치 검정 (Grubbs) ──',
'grubbs <- function(x, alpha = 0.05) {',
'  n <- length(x); s <- sd(x)',
'  if (s == 0) return(list(G = 0, crit = NA, value = NA, passed = TRUE))',
'  dev <- abs(x - mean(x)) / s; G <- max(dev); i <- which.max(dev)',
'  tc <- qt(1 - alpha/(2*n), n - 2)',
'  crit <- ((n - 1)/sqrt(n)) * sqrt(tc^2 / (n - 2 + tc^2))',
'  list(G = G, crit = crit, value = x[i], passed = G <= crit)',
'}',
'gr_all <- grubbs(as.vector(values), alpha)',
'gr_mean <- grubbs(rowMeans(values), alpha)',
'',
'# ── z-score (ISO 13528 Algorithm A) ──',
'algorithm_a <- function(x) {',
'  p <- length(x); xs <- median(x); ss <- 1.483 * median(abs(x - xs))',
'  for (i in 1:50) {',
'    if (ss == 0) break',
'    d <- 1.5 * ss; w <- pmin(pmax(x, xs - d), xs + d)',
'    nx <- mean(w); nsd <- 1.134 * sqrt(sum((w - nx)^2)/(p - 1))',
'    done <- abs(nx - xs) < 1e-10 && abs(nsd - ss) < 1e-10',
'    xs <- nx; ss <- nsd; if (done) break',
'  }',
'  list(mean = xs, sd = ss)',
'}',
'# 절차서에 목표 재현성이 규정되어 있으면 아래 sigma 를 그 값으로 바꾼다.',
'est <- algorithm_a(rowMeans(values))',
'assigned <- est$mean; sigma <- est$sd',
'zs <- (rowMeans(values) - assigned) / sigma',
'flag <- ifelse(abs(zs) < 2, "만족", ifelse(abs(zs) < 3, "경고", "부적합"))',
'',
'# ── 보고서 출력 ──',
'cat("\\n=== 비교숙련도 판정 보고서 ===\\n")',
'cat("단위:", unit_label, " | 시험자", length(analysts), "명 x", ncol(values), "개\\n")',
'cat("유의수준 alpha =", alpha, " 동등성 한계 delta = +-", delta, "\\n\\n")',
'',
'cat("[1] 시험자별 요약\\n")',
'print(data.frame(평균 = rowMeans(values), 표준편차 = apply(values, 1, sd),',
'                 z = round(zs, 2), 판정 = flag))',
'',
'cat("\\n[2] 숙련도 판정 (ISO/IEC 17043, 주 판정)\\n")',
'cat("  기준값", round(assigned, 4), " sigma", round(sigma, 4),',
'    " 최대 |z| =", round(max(abs(zs)), 2), "->",',
'    if (all(flag == "만족")) "전원 만족" else "부적합/경고 있음", "\\n")',
'',
'cat("\\n[3] 등분산 검정 (Levene)\\n")',
'cat("  통계량", round(lev[["F value"]][1], 4), " P =", round(lev[["Pr(>F)"]][1], 5),',
'    "->", if (lev[["Pr(>F)"]][1] > alpha) "등분산" else "이분산", "\\n")',
'',
'cat("\\n[4] 일원 분산분석\\n")',
'print(fit)',
'cat("  주의: 분산분석이 검정하는 것은 평균이지 분산이 아니다.\\n")',
'cat("  P > alpha 는 차이를 찾지 못했다는 뜻이지 차이가 없다는 증명이 아니다.\\n")',
'',
'cat("\\n[5] 동등성 검정 (TOST)\\n")',
'print(pairs)',
'cat("  최대 P =", round(max(pairs$p), 5), " 최대 평균차 =", round(max(abs(pairs$diff)), 4),',
'    "->", if (max(pairs$p) < alpha) "동등성 입증" else "동등성 미입증", "\\n")',
'',
'cat("\\n[6] 이상치 검정 (Grubbs)\\n")',
'cat("  전체:", round(gr_all$G, 4), "/ 임계", round(gr_all$crit, 4),',
'    "->", if (gr_all$passed) "이상치 아님" else "이상치", "\\n")',
'cat("  평균:", round(gr_mean$G, 4), "/ 임계", round(gr_mean$crit, 4),',
'    "->", if (gr_mean$passed) "이상치 아님" else "이상치", "\\n")',
'if (gr_all$passed && gr_mean$passed) {',
'  cat("  통계적 이상치가 없으므로 값을 제외할 근거가 없다. 전부 보고에 포함한다.\\n")',
'}',
'',
'# Word 보고서가 필요하면 rmarkdown 과 pandoc 을 설치한 뒤',
'# proficiency/R/report.Rmd 를 render 한다 (RStudio 를 깔면 pandoc 이 함께 들어온다).'
    ].join('\n');
  }

  function download(name, text, mime) {
    var blob = new Blob([text], { type: (mime || 'text/plain') + ';charset=utf-8' });
    var url = URL.createObjectURL(blob);
    var a = document.createElement('a');
    a.href = url; a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(function () { URL.revokeObjectURL(url); }, 1000);
  }

  $('btnCopy').addEventListener('click', function () {
    navigator.clipboard.writeText($('rcode').textContent).then(function () {
      var b = $('btnCopy'); var t = b.textContent;
      b.textContent = '복사됨'; setTimeout(function () { b.textContent = t; }, 1400);
    });
  });
  $('btnDownload').addEventListener('click', function () {
    download('proficiency_' + state.result.spec.seed + '.R', $('rcode').textContent);
  });
  $('btnCsv').addEventListener('click', function () {
    var r = state.result;
    var lines = ['시험자,순서,시료,시편ID,스크리닝값,측정값'];
    r.rows.slice().sort(function (a, b) {
      return a.analyst.localeCompare(b.analyst) || a.order - b.order;
    }).forEach(function (x) {
      lines.push([x.analyst, x.order, x.sample, x.id, x.screen, ''].join(','));
    });
    download('allocation_' + r.spec.seed + '.csv', '﻿' + lines.join('\n'), 'text/csv');
  });

  // ==========================================================================
  // 모드 B — 시험 후 판정
  // ==========================================================================

  var J = window.ProfJudge;
  var jState = { result: null };

  function setMode(toB) {
    $('tabA').classList.toggle('on', !toB);
    $('tabB').classList.toggle('on', toB);
    $('modeA').classList.toggle('hidden', toB);
    $('modeB').classList.toggle('hidden', !toB);
  }
  $('tabA').addEventListener('click', function () { setMode(false); });
  $('tabB').addEventListener('click', function () { setMode(true); });

  fillSelect('jAnalysts', 3, 5, 5);
  fillSelect('jSamples', 3, 5, 3);
  fillSelect('jDishes', 1, 3, 2);

  function jExpected() { return +$('jSamples').value * +$('jDishes').value; }

  function jUpdateNote() {
    var n = jExpected(), k = +$('jAnalysts').value;
    $('jNeedNote').innerHTML =
      '시험자 1인당 측정값 <strong>' + n + '개</strong> (시료 ' + $('jSamples').value +
      ' × 페트리 ' + $('jDishes').value + '). 시험자 ' + k + '명이면 모두 <strong>' +
      (n * k) + '개</strong>.';
  }

  // 입력칸을 다시 그린다. 이미 넣은 값과 이름은 살린다.
  function jBuildBoxes() {
    var k = +$('jAnalysts').value, wrap = $('jBoxes');
    var keep = [];
    wrap.querySelectorAll('.box').forEach(function (b) {
      keep.push({ name: b.querySelector('.name').value,
                  text: b.querySelector('textarea').value });
    });
    wrap.innerHTML = '';
    for (var i = 0; i < k; i++) {
      var box = document.createElement('div');
      box.className = 'box';

      var name = document.createElement('input');
      name.className = 'name';
      name.setAttribute('aria-label', '시험자 이름');
      name.value = keep[i] ? keep[i].name : String.fromCharCode(65 + i);

      var ta = document.createElement('textarea');
      ta.placeholder = '숫자를 엔터로\n구분해 붙여넣기';
      ta.value = keep[i] ? keep[i].text : '';
      ta.addEventListener('input', jUpdateCounts);

      var cnt = document.createElement('div');
      cnt.className = 'count';

      box.appendChild(name); box.appendChild(ta); box.appendChild(cnt);
      wrap.appendChild(box);
    }
    jUpdateCounts();
  }

  function jReadGroups() {
    return Array.prototype.map.call($('jBoxes').querySelectorAll('.box'), function (b, i) {
      var p = J.parseNumbers(b.querySelector('textarea').value);
      return { name: b.querySelector('.name').value.trim() || String.fromCharCode(65 + i),
               values: p.values, invalid: p.invalid };
    });
  }

  function jUpdateCounts() {
    var want = jExpected(), cells = $('jBoxes').querySelectorAll('.count');
    jReadGroups().forEach(function (g, i) {
      var n = g.values.length, txt = n + ' / ' + want + '개', cls = 'count';
      if (g.invalid.length) { cls += ' bad'; txt += ' · 숫자 아닌 값 ' + g.invalid.length + '개'; }
      else if (n === want) cls += ' ok';
      else if (n > 0) cls += ' bad';
      cells[i].className = cls;
      cells[i].textContent = txt;
    });
  }

  ['jAnalysts', 'jSamples', 'jDishes'].forEach(function (id) {
    $(id).addEventListener('change', function () { jUpdateNote(); jBuildBoxes(); });
  });
  jUpdateNote();
  jBuildBoxes();

  $('jClear').addEventListener('click', function () {
    $('jBoxes').querySelectorAll('textarea').forEach(function (t) { t.value = ''; });
    $('jResults').classList.add('hidden');
    $('jReportSection').classList.add('hidden');
    $('jMsg').classList.add('hidden');
    jUpdateCounts();
  });

  $('jDemo').addEventListener('click', function () {
    var want = jExpected(), cfu = $('jUnit').value === 'cfu';
    var rnd = S.mulberry32(20260914);
    $('jBoxes').querySelectorAll('textarea').forEach(function (t, ai) {
      // 마지막 시험자에게만 치우침을 준다 — 판정이 그것을 잡아내는지 보기 위함이다.
      var k = $('jBoxes').querySelectorAll('textarea').length;
      var bias = ai === k - 1 ? 0.22 : 0;
      var out = [];
      for (var j = 0; j < want; j++) {
        out.push(cfu
          ? String(Math.max(31, Math.round(S.gauss(rnd, 180, 30) * Math.pow(10, bias))))
          : S.gauss(rnd, bias, 0.14).toFixed(2));
      }
      t.value = out.join('\n');
    });
    jUpdateCounts();
  });

  function jRun() {
    var msg = $('jMsg'), want = jExpected(), gs = jReadGroups(), problems = [];
    gs.forEach(function (g) {
      if (g.invalid.length) {
        problems.push(g.name + ': 숫자가 아닌 값 (' + g.invalid.slice(0, 3).join(', ') + ')');
      } else if (g.values.length !== want) {
        problems.push(g.name + ': ' + g.values.length + '개 (기대 ' + want + '개)');
      }
    });
    if (problems.length) {
      msg.textContent = problems.join(' · ');
      msg.classList.remove('hidden');
      return;
    }
    try {
      jState.result = J.analyze(
        gs.map(function (g) { return g.name; }),
        gs.map(function (g) { return g.values; }),
        { inputType: $('jUnit').value, delta: +$('jDelta').value, alpha: +$('jAlpha').value });
    } catch (e) {
      msg.textContent = e.message;
      msg.classList.remove('hidden');
      return;
    }
    msg.classList.add('hidden');
    jRender();
  }
  $('jRun').addEventListener('click', jRun);

  // --- 모드 B 출력 -------------------------------------------------------------

  function sgn(x, d) {
    if (x === null || x === undefined || isNaN(x)) return '-';
    return (x >= 0 ? '+' : '') + x.toFixed(d === undefined ? 4 : d);
  }
  function verdict(t) { return t.passed ? '적합' : '부적합'; }

  function jRender() {
    var r = jState.result, h = [];
    var worstZ = Math.max.apply(null, r.z.scores.map(function (s) { return Math.abs(s.z); }));
    var zOk = worstZ < 2;

    if (r.countWarnings.length) {
      h.push('<p class="note bad"><strong>경고</strong> 계수 유효범위(' + J.COUNT_MIN + '~' +
             J.COUNT_MAX + ') 이탈: ' +
             r.countWarnings.map(function (w) {
               return esc(w.name) + ' — ' + w.values.join(', ');
             }).join(' / ') + '. 희석 단계를 다시 확인해야 합니다.</p>');
    }

    h.push('<h2>3. 시험자별 요약</h2><div class="card">');
    h.push('<div class="tablewrap"><table><tr><th>시험자</th><th class="num">평균</th>' +
           '<th class="num">표준편차</th><th class="num">z-score</th><th>판정</th></tr>');
    r.names.forEach(function (name, i) {
      var s = r.z.scores[i];
      var cls = s.flag === '만족' ? 'ok' : s.flag === '경고' ? 'wa' : 'no';
      h.push('<tr><th>' + esc(name) + '</th><td class="num">' + sgn(r.means[i]) +
             '</td><td class="num">' + f(r.stdevs[i]) + '</td><td class="num">' + sgn(s.z, 2) +
             '</td><td><span class="' + cls + '">' + s.flag + '</span></td></tr>');
    });
    h.push('</table></div>');
    h.push('<p class="spare" style="font-size:13px">단위 ' + esc(r.unit) +
           ' · 기준값(로버스트 평균) ' + sgn(r.z.assigned) +
           ', 로버스트 표준편차 ' + f(r.z.sigma) + ' (ISO 13528 Algorithm A)</p></div>');

    h.push('<h2>4. 숙련도 판정</h2><div class="card">');
    h.push('<p>최대 |z| = <strong>' + worstZ.toFixed(2) + '</strong> → <strong>' +
           (zOk ? '<span class="ok">전원 만족</span>' : '<span class="no">부적합자 있음</span>') +
           '</strong></p>');
    h.push('<p class="spare" style="font-size:13px">|z| &lt; 2 만족, 2 ≤ |z| &lt; 3 경고, ' +
           '|z| ≥ 3 부적합 (ISO/IEC 17043 주 판정)</p>');

    h.push('<h3>보조 검정</h3><div class="tablewrap"><table>' +
           '<tr><th>검정</th><th class="num">통계량</th><th class="num">p-value</th>' +
           '<th>결과</th><th>의미</th></tr>');
    [[r.levene, '시험자 간 산포가 같은가'],
     [r.anova, '평균 차이가 탐지되는가'],
     [r.tost, '평균이 δ 이내로 동등한가']].forEach(function (x) {
      var t = x[0];
      h.push('<tr><td>' + esc(t.name) + '</td><td class="num">' + f(t.statistic) +
             '</td><td class="num">' + f(t.pValue, 5) + '</td><td><span class="' +
             (t.passed ? 'ok' : 'no') + '">' + verdict(t) + '</span></td><td>' + x[1] + '</td></tr>');
    });
    h.push('</table></div>');
    h.push('<p class="note">분산분석의 “적합”은 차이를 <strong>찾지 못했다</strong>는 뜻이지 ' +
           '차이가 <strong>없다</strong>는 증명이 아닙니다. 차이 없음의 입증은 TOST 가 담당합니다.</p>');

    var ga = r.grubbsAll, gm = r.grubbsMeans;
    h.push('<h3>이상치 검정 (Grubbs)</h3><ul style="margin:0;padding-left:20px;font-size:13px">');
    h.push('<li>전체 측정값: G = ' + f(ga.statistic) + ' (임계 ' + f(ga.critical) +
           '), 최대편차 ' + sgn(ga.value) + ' (' + esc(r.grubbsAllOwner) + ') → <strong class="' +
           (ga.passed ? 'ok' : 'no') + '">' + verdict(ga) + '</strong></li>');
    h.push('<li>시험자 평균: G = ' + f(gm.statistic) + ' (임계 ' + f(gm.critical) +
           '), 최대편차 ' + sgn(gm.value) + ' (' + esc(r.names[gm.index]) + ') → <strong class="' +
           (gm.passed ? 'ok' : 'no') + '">' + verdict(gm) + '</strong></li></ul>');
    if (ga.passed && gm.passed) {
      h.push('<p class="note">통계적 이상치가 없습니다. 눈에 띄는 값이 있더라도 ' +
             '<strong>제외할 근거가 없으므로 모두 보고에 포함해야 합니다.</strong></p>');
    }
    h.push('</div>');

    h.push('<h2>5. 진단 — 무작위 재배정 통과율</h2><div class="card">');
    h.push('<p>전체 값을 무작위로 재배정했을 때 현행 기준(등분산+분산분석) 통과율: <strong>' +
           pct(r.randomRate) + '</strong> · 실제 배정: <strong class="' +
           (r.classicPass ? 'ok' : 'no') + '">' + (r.classicPass ? '통과' : '탈락') +
           '</strong> <span class="spare">(' + r.trials.toLocaleString() + '회 시행)</span></p>');
    h.push('<p class="note' + (r.randomRate >= 0.5 && !r.classicPass ? ' bad'
           : r.randomRate < 0.5 ? ' warn' : '') + '">' + esc(diagnosis(r)) + '</p>');
    h.push('</div>');

    $('jResults').innerHTML = h.join('');
    $('jResults').classList.remove('hidden');
    $('jReport').textContent = jMarkdown();
    $('jReportSection').classList.remove('hidden');
  }

  /* 무작위 재배정 통과율의 해석. judge.py 의 진단문과 같은 기준으로 가른다. */
  function diagnosis(r) {
    if (r.randomRate >= 0.5 && !r.classicPass) {
      return '무작위로 섞으면 ' + Math.round(r.randomRate * 100) +
        '% 가 통과하는데 실제 배정만 탈락했습니다. 우연이 아니라 시험자별 체계적 편향이 ' +
        '실재한다는 뜻입니다. 배정을 바꿔 통과시키는 것은 이 편향을 은폐하는 것이므로, ' +
        '편향의 원인(접종액 조제, 세척 회수, 판독 습관 등)을 조사해야 합니다.';
    }
    if (r.randomRate < 0.5) {
      return '무작위 배정으로도 절반 이상 탈락합니다. 전체 산포 자체가 커서 어떤 배정으로도 ' +
        '정당하게 통과할 수 없습니다. 기법 표준화가 먼저입니다.';
    }
    return '전체 산포가 충분히 작고 실제 배정도 통과했습니다.';
  }

  /* judge.py 의 format_report 와 같은 순서·같은 내용의 Markdown 보고서. */
  function jMarkdown() {
    var r = jState.result, L = [];
    var worstZ = Math.max.apply(null, r.z.scores.map(function (s) { return Math.abs(s.z); }));

    L.push('# 비교숙련도 판정 보고서', '');
    L.push('- 입력 단위: ' + r.unit);
    L.push('- 시험자 ' + r.names.length + '명 × 측정값 ' + r.nPerAnalyst + '개');
    L.push('- 유의수준 α = ' + r.alpha + ', 동등성 한계 δ = ±' + r.delta);
    L.push('- 생성일: ' + new Date().toISOString().slice(0, 10), '');

    if (r.countWarnings.length) {
      L.push('> **경고** 계수 유효범위(' + J.COUNT_MIN + '~' + J.COUNT_MAX + ') 이탈:');
      r.countWarnings.forEach(function (w) {
        L.push('> - ' + w.name + ': ' + w.values.join(', '));
      });
      L.push('');
    }

    L.push('## 1. 시험자별 요약', '');
    L.push('| 시험자 | 평균 | 표준편차 | z-score | 판정 |');
    L.push('|---|---:|---:|---:|---|');
    r.names.forEach(function (name, i) {
      L.push('| ' + name + ' | ' + sgn(r.means[i]) + ' | ' + f(r.stdevs[i]) + ' | ' +
             sgn(r.z.scores[i].z, 2) + ' | ' + r.z.scores[i].flag + ' |');
    });
    L.push('');
    L.push('기준값(로버스트 평균) = ' + sgn(r.z.assigned) + ', 로버스트 표준편차 = ' +
           f(r.z.sigma) + ' (ISO 13528 Algorithm A)', '');

    L.push('## 2. 숙련도 판정 (ISO/IEC 17043 주 판정)', '');
    L.push('- 최대 |z| = ' + worstZ.toFixed(2));
    L.push('- **판정: ' + (worstZ < 2 ? '전원 만족' : '부적합자 있음') +
           '** (|z| < 2 만족, 2 ≤ |z| < 3 경고, |z| ≥ 3 부적합)', '');

    L.push('## 3. 보조 검정', '');
    L.push('| 검정 | 통계량 | p-value | 결과 | 의미 |');
    L.push('|---|---:|---:|---|---|');
    [[r.levene, '시험자 간 산포가 같은가'],
     [r.anova, '평균 차이가 탐지되는가'],
     [r.tost, '평균이 δ 이내로 동등한가']].forEach(function (x) {
      L.push('| ' + x[0].name + ' | ' + f(x[0].statistic) + ' | ' + f(x[0].pValue, 5) +
             ' | ' + verdict(x[0]) + ' | ' + x[1] + ' |');
    });
    L.push('');
    L.push('ANOVA 의 \'적합\'은 차이를 **찾지 못했다**는 뜻이지 차이가 **없다**는 증명이 아니다. ' +
           '차이 없음의 입증은 TOST 가 담당한다.', '');

    var ga = r.grubbsAll, gm = r.grubbsMeans;
    L.push('## 4. 이상치 검정 (Grubbs)', '');
    L.push('- 전체 측정값: G = ' + f(ga.statistic) + ' (임계 ' + f(ga.critical) +
           '), 최대편차 ' + sgn(ga.value) + ' (' + r.grubbsAllOwner + ') → **' + verdict(ga) + '**');
    L.push('- 시험자 평균: G = ' + f(gm.statistic) + ' (임계 ' + f(gm.critical) +
           '), 최대편차 ' + sgn(gm.value) + ' (' + r.names[gm.index] + ') → **' + verdict(gm) + '**');
    L.push('');
    if (ga.passed && gm.passed) {
      L.push('통계적 이상치가 없다. 눈에 띄는 값이 있더라도 **제외할 근거가 없으므로 ' +
             '모두 보고에 포함해야 한다.**', '');
    }

    L.push('## 5. 진단 — 무작위 재배정 통과율', '');
    L.push('- 전체 값을 무작위로 재배정했을 때 현행 기준(등분산+ANOVA) 통과율: **' +
           pct(r.randomRate) + '** (' + r.trials.toLocaleString() + '회 시행)');
    L.push('- 실제 배정: **' + (r.classicPass ? '통과' : '탈락') + '**', '');
    L.push('> ' + diagnosis(r), '');

    return L.join('\n');
  }

  $('jCopy').addEventListener('click', function () {
    navigator.clipboard.writeText($('jReport').textContent).then(function () {
      var b = $('jCopy'), t = b.textContent;
      b.textContent = '복사됨'; setTimeout(function () { b.textContent = t; }, 1400);
    });
  });
  $('jDownload').addEventListener('click', function () {
    download('proficiency_report_' + new Date().toISOString().slice(0, 10) + '.md',
             $('jReport').textContent, 'text/markdown');
  });
  // judge.py 가 그대로 읽을 수 있는 형식으로 내보낸다.
  $('jCsv').addEventListener('click', function () {
    var gs = jReadGroups(), n = jExpected();
    var lines = ['분석자,' + Array.from({ length: n }, function (_, i) { return i + 1; }).join(',')];
    gs.forEach(function (g) { lines.push([g.name].concat(g.values).join(',')); });
    download('measurements_' + new Date().toISOString().slice(0, 10) + '.csv',
             '﻿' + lines.join('\n'), 'text/csv');
  });
})();
VERIFY_EOF_VERIFY_APP_JS

echo ""
echo "설치 완료: $DEST"
for f in verify.html verify-stats.js verify-judge.js verify-app.js; do
  printf "  %s (%s bytes)\n" "$f" "$(wc -c < "$DEST/$f" | tr -d " ")"
done

# 다시 설치할 수 있도록 스크립트를 프로젝트 안에 둔다.
SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"
KEEP="$ROOT/tools/install-verify.sh"
if [ "$SELF" != "$KEEP" ]; then
  mkdir -p "$ROOT/tools"
  cp "$SELF" "$KEEP"
  echo "재설치용 사본: $KEEP"
fi

# build.mjs 가 public 을 비우는지 확인해 알려준다.
if [ -f "$ROOT/build.mjs" ] && grep -qE "rm[A-Za-z]*\(|rimraf|emptyDir" "$ROOT/build.mjs"; then
  echo ""
  echo "주의: build.mjs 가 public 을 지웁니다. 빌드할 때마다 이 파일들이 사라집니다."
  echo "      package.json 의 scripts 에 아래 한 줄을 넣어두면 빌드 후 자동 복구됩니다."
  echo '        "postbuild": "bash tools/install-verify.sh ."'
  echo "      (빌드 명령이 npm run build 가 아니라면 그 명령 뒤에 직접 이어 붙이세요.)"
fi

echo ""
echo "확인:  cd $DEST && python3 -m http.server 8000"
echo "       http://localhost:8000/verify.html  (비밀번호 bioplug2026)"
echo ""
echo "배포:  cd $ROOT && node build.mjs && npx vercel --prod --yes"
echo "       https://bioplug.vercel.app/verify"
echo ""
echo "탭 링크는 build.mjs 의 tabsHTML() 이 verify.html 유무를 보고 넣습니다."

"""모드 B — 비교숙련도 판정기.

분석자별 결과를 입력받아 ISO/IEC 17043 · ISO 13528 방식으로 판정하고
Markdown 보고서를 출력한다.

입력 형식 (CSV, 첫 열은 분석자명, 나머지 열은 측정값):

    분석자,1,2,3,4,5,6
    A,-0.14,-0.12,-0.04,-0.06,0.06,0.12
    B,0.28,0.22,0.19,0.14,-0.06,-0.16

사용법:

    python3 judge.py data.csv --type r
    python3 judge.py data.csv --type cfu --delta 0.25

--type r    : ISO 22196 의 R(항균활성). 이미 log 단위이므로 변환하지 않는다.
--type cfu  : 원 집락수. log10 변환 후 검정한다.
"""

from __future__ import annotations

import argparse
import csv
import math
import random
import sys

import cfu_stats as cs

DEFAULT_DELTA = 0.25
DEFAULT_ALPHA = 0.05
DEFAULT_TRIALS = 100_000
COUNT_MIN, COUNT_MAX = 30, 300


HEADER_KEYS = {"분석자", "담당자", "이름", "성명", "name", "analyst"}


def read_csv(path):
    """CSV 를 (분석자명 목록, 값 그룹 목록) 으로 읽는다.

    열 이름이 1,2,3... 처럼 숫자일 수 있으므로, 헤더 판별은 값의 숫자 여부가
    아니라 첫 칸의 이름으로 한다.
    """
    names, groups = [], []
    first_row = True
    with open(path, newline="", encoding="utf-8-sig") as fh:
        for row in csv.reader(fh):
            cells = [c.strip() for c in row if c.strip() != ""]
            if not cells:
                continue
            if first_row:
                first_row = False
                if cells[0].lower() in HEADER_KEYS:
                    continue
            if len(cells) < 2 or not all(_is_number(c) for c in cells[1:]):
                continue  # 헤더나 주석 줄
            names.append(cells[0])
            groups.append([float(c) for c in cells[1:]])
    if not groups:
        raise ValueError("자료 행을 찾지 못했습니다. CSV 형식을 확인하세요.")
    sizes = {len(g) for g in groups}
    if len(sizes) != 1:
        raise ValueError(f"분석자마다 측정값 개수가 다릅니다: {sorted(sizes)}")
    if sizes.pop() < 2:
        raise ValueError(
            "분석자당 측정값이 1개뿐이면 그룹 내 변동을 추정할 수 없어 "
            "분산분석이 성립하지 않습니다."
        )
    return names, groups


def _is_number(s):
    try:
        float(s)
        return True
    except ValueError:
        return False


def prepare(groups, input_type):
    """입력 타입에 맞게 값을 변환한다. R 은 이미 log 단위이므로 변환하지 않는다."""
    if input_type == "cfu":
        return [cs.log10_counts(g) for g in groups], "log10(CFU)"
    return [list(g) for g in groups], "R (항균활성, log 단위)"


def count_range_warnings(groups, names):
    """집락수 유효범위(30~300) 이탈을 경고로 모은다."""
    out = []
    for name, g in zip(names, groups):
        bad = [v for v in g if not (COUNT_MIN <= v <= COUNT_MAX)]
        if bad:
            out.append((name, bad))
    return out


def passes_classic(groups, alpha=DEFAULT_ALPHA):
    """현행 판정 기준(등분산 + ANOVA)을 통과하는지."""
    return cs.levene(groups, alpha=alpha).passed and cs.anova_oneway(groups, alpha=alpha).passed


def random_reallocation_rate(groups, trials=DEFAULT_TRIALS, seed=20260914, alpha=DEFAULT_ALPHA):
    """전체 값을 무작위로 재배정했을 때 현행 기준을 통과하는 비율.

    실제 배정이 이 분포의 어디에 있는지가 진단의 핵심이다.
    통과율이 높은데 실제 배정만 탈락한다면, 우연이 아니라 분석자별
    체계적 편향이 실재한다는 뜻이다.
    """
    pool = [v for g in groups for v in g]
    n = len(groups[0])
    k = len(groups)
    rng = random.Random(seed)
    hit = 0
    for _ in range(trials):
        rng.shuffle(pool)
        if passes_classic([pool[i * n:(i + 1) * n] for i in range(k)], alpha=alpha):
            hit += 1
    return hit / trials


def analyze(names, raw_groups, input_type="r", delta=DEFAULT_DELTA,
            alpha=DEFAULT_ALPHA, trials=DEFAULT_TRIALS):
    """전체 판정을 수행하고 결과 딕셔너리를 반환한다."""
    groups, unit = prepare(raw_groups, input_type)
    means = [cs.mean(g) for g in groups]

    flat = [v for g in groups for v in g]
    grubbs_all = cs.grubbs(flat)
    # 같은 값이 여러 번 나올 수 있으므로 검정이 돌려준 인덱스를 그대로 쓴다.
    owner_idx = grubbs_all.detail["index"] // len(groups[0])

    return {
        "names": names,
        "unit": unit,
        "input_type": input_type,
        "alpha": alpha,
        "delta": delta,
        "n_per_analyst": len(groups[0]),
        "means": means,
        "stdevs": [cs.stdev(g) for g in groups],
        "levene": cs.levene(groups, alpha=alpha),
        "anova": cs.anova_oneway(groups, alpha=alpha),
        "tost": cs.tost_all_pairs(groups, delta=delta, alpha=alpha),
        "grubbs_all": grubbs_all,
        "grubbs_all_owner": names[owner_idx],
        "grubbs_means": cs.grubbs(means, alpha=alpha),
        "z": cs.z_scores(means),
        "classic_pass": passes_classic(groups, alpha=alpha),
        "random_rate": random_reallocation_rate(groups, trials=trials, alpha=alpha),
        "count_warnings": (
            count_range_warnings(raw_groups, names) if input_type == "cfu" else []
        ),
    }


def _row(cells, widths):
    return "| " + " | ".join(str(c).ljust(w) for c, w in zip(cells, widths)) + " |"


def format_report(res):
    """판정 결과를 Markdown 보고서로 만든다."""
    L = []
    L.append("# 비교숙련도 판정 보고서")
    L.append("")
    L.append(f"- 입력 단위: {res['unit']}")
    L.append(f"- 분석자 {len(res['names'])}명 × 측정값 {res['n_per_analyst']}개")
    L.append(f"- 유의수준 α = {res['alpha']}, 동등성 한계 δ = ±{res['delta']}")
    L.append("")

    if res["count_warnings"]:
        L.append(f"> **경고** 계수 유효범위({COUNT_MIN}~{COUNT_MAX}) 이탈:")
        for name, bad in res["count_warnings"]:
            L.append(f"> - {name}: {', '.join(str(int(b)) for b in bad)}")
        L.append("")

    L.append("## 1. 분석자별 요약")
    L.append("")
    L.append("| 분석자 | 평균 | 표준편차 | z-score | 판정 |")
    L.append("|---|---:|---:|---:|---|")
    for name, m, s, zs in zip(res["names"], res["means"], res["stdevs"], res["z"]["scores"]):
        L.append(f"| {name} | {m:+.4f} | {s:.4f} | {zs['z']:+.2f} | {zs['flag']} |")
    L.append("")
    L.append(f"기준값(로버스트 평균) = {res['z']['assigned']:+.4f}, "
             f"로버스트 표준편차 = {res['z']['sigma']:.4f} (ISO 13528 Algorithm A)")
    L.append("")

    L.append("## 2. 숙련도 판정 (ISO/IEC 17043 주 판정)")
    L.append("")
    worst = max(abs(s["z"]) for s in res["z"]["scores"])
    z_ok = worst < 2.0
    L.append(f"- 최대 |z| = {worst:.2f}")
    L.append(f"- **판정: {'전원 만족' if z_ok else '부적합자 있음'}** "
             f"(|z| < 2 만족, 2 ≤ |z| < 3 경고, |z| ≥ 3 부적합)")
    L.append("")

    L.append("## 3. 보조 검정")
    L.append("")
    L.append("| 검정 | 통계량 | p-value | 결과 | 의미 |")
    L.append("|---|---:|---:|---|---|")
    for key, meaning in (
        ("levene", "분석자 간 산포가 같은가"),
        ("anova", "평균 차이가 탐지되는가"),
        ("tost", "평균이 δ 이내로 동등한가"),
    ):
        r = res[key]
        L.append(f"| {r.name} | {r.statistic:.4f} | {r.p_value:.5f} | {r.verdict()} | {meaning} |")
    L.append("")
    L.append("ANOVA 의 '적합'은 차이를 **찾지 못했다**는 뜻이지 차이가 **없다**는 증명이 아니다. "
             "차이 없음의 입증은 TOST 가 담당한다.")
    L.append("")

    L.append("## 4. 이상치 검정 (Grubbs)")
    L.append("")
    ga, gm = res["grubbs_all"], res["grubbs_means"]
    L.append(f"- 전체 측정값: G = {ga.statistic:.4f} (임계 {ga.detail['critical']:.4f}), "
             f"최대편차 {ga.detail['value']:+.4f} ({res['grubbs_all_owner']}) → **{ga.verdict()}**")
    L.append(f"- 분석자 평균: G = {gm.statistic:.4f} (임계 {gm.detail['critical']:.4f}), "
             f"최대편차 {gm.detail['value']:+.4f} ({res['names'][gm.detail['index']]}) → **{gm.verdict()}**")
    L.append("")
    if ga.passed and gm.passed:
        L.append("통계적 이상치가 없다. 눈에 띄는 값이 있더라도 **제외할 근거가 없으므로 "
                 "모두 보고에 포함해야 한다.**")
    L.append("")

    L.append("## 5. 진단 — 무작위 재배정 통과율")
    L.append("")
    rate = res["random_rate"]
    L.append(f"- 전체 값을 무작위로 재배정했을 때 현행 기준(등분산+ANOVA) 통과율: **{rate*100:.1f}%**")
    L.append(f"- 실제 배정: **{'통과' if res['classic_pass'] else '탈락'}**")
    L.append("")
    if rate >= 0.5 and not res["classic_pass"]:
        L.append(f"> 무작위로 섞으면 {rate*100:.0f}% 가 통과하는데 실제 배정만 탈락했다. "
                 "우연이 아니라 **분석자별 체계적 편향이 실재한다**는 뜻이다. "
                 "배정을 바꿔서 통과시키는 것은 이 편향을 은폐하는 것이므로, "
                 "편향의 원인(접종액 조제, 세척 회수, 판독 습관 등)을 조사해야 한다.")
    elif rate < 0.5:
        L.append("> 무작위 배정으로도 절반 이상 탈락한다. 전체 산포 자체가 커서 "
                 "**어떤 배정으로도 정당하게 통과할 수 없다.** 기법 표준화가 먼저다.")
    else:
        L.append("> 전체 산포가 충분히 작고 실제 배정도 통과했다.")
    L.append("")
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(description="비교숙련도 판정기 (모드 B)")
    ap.add_argument("csv_path", help="입력 CSV 경로")
    ap.add_argument("--type", dest="input_type", choices=("r", "cfu"), default="r",
                    help="r=항균활성 R(변환 없음), cfu=원 집락수(log10 변환)")
    ap.add_argument("--delta", type=float, default=DEFAULT_DELTA, help="동등성 한계 (log 단위)")
    ap.add_argument("--alpha", type=float, default=DEFAULT_ALPHA, help="유의수준")
    ap.add_argument("--trials", type=int, default=DEFAULT_TRIALS, help="무작위 재배정 시행 횟수")
    ap.add_argument("-o", "--output", help="보고서 저장 경로 (미지정 시 표준출력)")
    args = ap.parse_args(argv)

    names, groups = read_csv(args.csv_path)
    res = analyze(names, groups, input_type=args.input_type, delta=args.delta,
                  alpha=args.alpha, trials=args.trials)
    report = format_report(res)

    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(report + "\n")
        print(f"보고서를 저장했습니다: {args.output}")
    else:
        print(report)
    return 0


if __name__ == "__main__":
    sys.exit(main())

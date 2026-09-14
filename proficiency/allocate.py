"""모드 A — 사전 배정기.

시험 **전에** 시편을 시험자에게 배정하고, 배정표와 라벨을 출력한다.
결과를 보고 배정을 고르는 것이 아니라, 배정을 먼저 확정하고 기록으로 남긴다.

두 가지를 한다.

1. 균형 배정 탐색
   각 시험자가 모든 시료를 같은 횟수만큼 받고(완전균형),
   시험 순서에 특정 시료가 몰리지 않도록(순서 균형) 배정을 찾는다.
   순서 균형은 무작위 재시작 탐색으로 최적화한다.

2. 사전 설계 검증
   시험 전에 "이 인원·반복수·목표 재현성으로 판정이 성립하는가"를
   몬테카를로로 계산한다. 반복수가 부족하면 시험 전에 알 수 있다.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import math
import random
import sys
from dataclasses import dataclass, field

import cfu_stats as cs

DEFAULT_ALPHA = 0.05
DEFAULT_DELTA = 0.25


# ---------------------------------------------------------------------------
# 1. 균형 배정
# ---------------------------------------------------------------------------

@dataclass
class Allocation:
    analysts: list
    samples: list
    reps: int
    rows: list = field(default_factory=list)      # dict(analyst, order, sample, specimen)
    spares: list = field(default_factory=list)    # dict(sample, specimen)
    seed: int = 0
    imbalance: float = 0.0

    @property
    def runs_per_analyst(self):
        return len(self.samples) * self.reps


def _order_imbalance(orders, samples):
    """순서별 시료 분포가 고를수록 작아지는 점수. 0 이면 완전 균형."""
    n_pos = len(orders[0])
    expected = len(orders) / len(samples)
    total = 0.0
    for pos in range(n_pos):
        counts = {s: 0 for s in samples}
        for row in orders:
            counts[row[pos]] += 1
        total += math.fsum((c - expected) ** 2 for c in counts.values())
    return total


def _build_orders(n_analysts, samples, reps, rng):
    """각 시험자의 시료 수행 순서를 만든다.

    순환 라틴 구성을 쓴다. 시험자 i, 순서 c 에 배정되는 시료는

        samples[(offset_i + c) mod ns]        (ns = 시료 종수)

    이 구성은 두 균형을 **동시에, 구성 자체로** 보장한다.

      * 행(시험자): c 가 0..ns*reps-1 을 돌면 각 나머지가 정확히 reps 번 나오므로
        각 시험자는 각 시료를 정확히 reps 개 받는다.
      * 열(순서): 한 열의 값은 offset_i 를 c 만큼 민 것이므로, 열의 시료 분포는
        offset 의 분포와 같다. offset 을 균형 있게 나눠주면 모든 열이
        floor(k/ns) ~ ceil(k/ns) 로 고르게 채워진다.

    무작위 재시작 탐색이나 단순 회전은 이 두 가지를 보장하지 못한다.
    무작위성은 시료 이름 섞기, offset 배정 섞기, 순서(열) 섞기로 준다.
    """
    ns = len(samples)
    labels = list(samples)
    rng.shuffle(labels)

    # offset 을 균형 있게 나눠준다: 0..ns-1 을 돌려 쓴 뒤 섞는다.
    offsets = [i % ns for i in range(n_analysts)]
    rng.shuffle(offsets)

    total = ns * reps
    positions = list(range(total))
    rng.shuffle(positions)

    orders = [[labels[(off + c) % ns] for c in positions] for off in offsets]
    return orders, _order_imbalance(orders, samples)


def make_allocation(analysts, samples, reps=2, spares_per_sample=0,
                    seed=None, prefix="S"):
    """배정표를 만든다.

    analysts          : 시험자 목록
    samples           : 시료(시험편) 목록
    reps              : 시험자 1인이 시료 1개당 수행할 반복수
    spares_per_sample : 시료당 여분 시편 수 (재시험용, 배정하지 않는다)
    """
    if reps < 1:
        raise ValueError("반복수는 1 이상이어야 합니다.")
    if len(samples) < 1:
        raise ValueError("시료가 1개 이상이어야 합니다.")
    if len(analysts) < 2:
        raise ValueError("시험자가 2명 이상이어야 합니다.")

    seed = random.randrange(2 ** 31) if seed is None else seed
    rng = random.Random(seed)

    orders, imbalance = _build_orders(len(analysts), samples, reps, rng)

    # 시료별 시편 풀을 만들고 무작위로 배정한다.
    pools = {}
    for s in samples:
        need = len(analysts) * reps
        ids = [f"{prefix}{s}-{i + 1:02d}" for i in range(need + spares_per_sample)]
        rng.shuffle(ids)
        pools[s] = ids

    rows = []
    for analyst, order in zip(analysts, orders):
        for pos, sample in enumerate(order, start=1):
            rows.append({
                "시험자": analyst,
                "순서": pos,
                "시료": sample,
                "시편ID": pools[sample].pop(),
            })

    spares = [{"시료": s, "시편ID": sid} for s in samples for sid in sorted(pools[s])]

    return Allocation(analysts=list(analysts), samples=list(samples), reps=reps,
                      rows=rows, spares=spares, seed=seed, imbalance=imbalance)


def check_balance(alloc):
    """배정이 균형 조건을 만족하는지 검사한다."""
    issues = []

    # 1. 각 시험자가 각 시료를 정확히 reps 개 받았는가
    for a in alloc.analysts:
        for s in alloc.samples:
            n = sum(1 for r in alloc.rows if r["시험자"] == a and r["시료"] == s)
            if n != alloc.reps:
                issues.append(f"{a} 의 시료 {s} 배정이 {n}개 (기대 {alloc.reps}개)")

    # 2. 시편 ID 중복 배정이 없는가
    ids = [r["시편ID"] for r in alloc.rows]
    if len(ids) != len(set(ids)):
        dup = sorted({i for i in ids if ids.count(i) > 1})
        issues.append(f"시편 ID 중복 배정: {', '.join(dup)}")

    # 3. 여분이 배정된 시편과 겹치지 않는가
    overlap = {r["시편ID"] for r in alloc.spares} & set(ids)
    if overlap:
        issues.append(f"여분이 배정과 겹침: {', '.join(sorted(overlap))}")

    # 4. 순서 균형
    expected = len(alloc.analysts) / len(alloc.samples)
    order_table = {}
    for pos in range(1, alloc.runs_per_analyst + 1):
        counts = {s: sum(1 for r in alloc.rows if r["순서"] == pos and r["시료"] == s)
                  for s in alloc.samples}
        order_table[pos] = counts
        if max(counts.values()) - min(counts.values()) > 1:
            issues.append(f"순서 {pos} 의 시료 분포 편중: {counts}")

    return {
        "passed": not issues,
        "issues": issues,
        "order_table": order_table,
        "expected_per_cell": expected,
    }


# ---------------------------------------------------------------------------
# 2. 사전 설계 검증
# ---------------------------------------------------------------------------

def simulate_design(n_analysts, reps_total, sigma_within, bias=0.0,
                    delta=DEFAULT_DELTA, alpha=DEFAULT_ALPHA, sigma_pt=None,
                    trials=2000, seed=20260914):
    """시험 전에 이 설계로 판정이 성립하는지 몬테카를로로 계산한다.

    sigma_within : 시험자 1인의 반복 간 표준편차 (목표 재현성, log 단위)
    bias         : 시험자 1명에게 부여할 계통 편향 크기. 0 이면 편향 없는 경우.
    sigma_pt     : z-score 판정용 규정 표준편차. None 이면 참가자 자료에서 추정.

    반환값의 의미
      anova_pass : 분산분석이 '차이 없음'으로 나올 비율
      tost_pass  : 동등성을 입증할 비율  <- 이 값이 낮으면 반복수가 부족하다
      z_pass     : 전원 |z| < 2 일 비율
    """
    rng = random.Random(seed)
    counters = {"anova_pass": 0, "tost_pass": 0, "z_pass": 0, "levene_pass": 0}

    for _ in range(trials):
        means = [0.0] * n_analysts
        if bias:
            means[0] = bias
        groups = [[rng.gauss(m, sigma_within) for _ in range(reps_total)] for m in means]

        if cs.levene(groups, alpha=alpha).passed:
            counters["levene_pass"] += 1
        if cs.anova_oneway(groups, alpha=alpha).passed:
            counters["anova_pass"] += 1
        if cs.tost_all_pairs(groups, delta=delta, alpha=alpha).passed:
            counters["tost_pass"] += 1

        gmeans = [cs.mean(g) for g in groups]
        z = cs.z_scores(gmeans, sigma=sigma_pt)
        if all(s["flag"] == "만족" for s in z["scores"]):
            counters["z_pass"] += 1

    return {k: v / trials for k, v in counters.items()}


def recommend_reps(n_analysts, sigma_within, delta=DEFAULT_DELTA, alpha=DEFAULT_ALPHA,
                   target=0.80, max_reps=24, trials=1000, seed=20260914):
    """동등성 입증 확률이 target 이상이 되는 최소 반복수를 찾는다.

    편향이 없는 이상적인 경우에도 이 반복수보다 적으면 동등성을 입증할 수 없다.
    """
    for reps in range(2, max_reps + 1):
        res = simulate_design(n_analysts, reps, sigma_within, bias=0.0,
                              delta=delta, alpha=alpha, trials=trials, seed=seed)
        if res["tost_pass"] >= target:
            return {"reps": reps, "tost_pass": res["tost_pass"], "achieved": True}
    return {"reps": None, "tost_pass": res["tost_pass"], "achieved": False}


def attainable_delta(n_analysts, reps_total, sigma_within, alpha=DEFAULT_ALPHA,
                     target=0.80, trials=600, seed=20260914,
                     lo=0.05, hi=3.0, steps=30):
    """이 설계로 입증 가능한 최소 동등성 한계를 찾는다.

    주의: delta 는 '통과할 때까지 늘리는 값'이 아니라 적합성 목적에 따라
    절차서에 규정하는 값이다. 이 함수는 규정값과 실제 달성 가능한 값의
    차이를 시험 전에 드러내기 위한 것이다. 둘이 벌어지면 답은 delta 를
    늘리는 것이 아니라 반복수를 늘리거나 시험 기법을 개선하는 것이다.
    """
    best = None
    for i in range(steps + 1):
        d = lo + (hi - lo) * i / steps
        res = simulate_design(n_analysts, reps_total, sigma_within, bias=0.0,
                              delta=d, alpha=alpha, trials=trials, seed=seed)
        if res["tost_pass"] >= target:
            best = {"delta": d, "tost_pass": res["tost_pass"], "achieved": True}
            break
    return best or {"delta": None, "tost_pass": 0.0, "achieved": False}


# ---------------------------------------------------------------------------
# 3. 출력
# ---------------------------------------------------------------------------

def write_allocation_csv(alloc, path):
    """배정표를 CSV 로 저장한다. 배지 라벨 출력용."""
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(["시험자", "순서", "시료", "시편ID", "측정값"])
        for r in sorted(alloc.rows, key=lambda x: (alloc.analysts.index(x["시험자"]), x["순서"])):
            w.writerow([r["시험자"], r["순서"], r["시료"], r["시편ID"], ""])
    return path


def write_results_template_csv(alloc, path):
    """측정 후 judge.py 에 그대로 넣을 수 있는 빈 결과표를 만든다."""
    with open(path, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.writer(fh)
        w.writerow(["분석자"] + [str(i) for i in range(1, alloc.runs_per_analyst + 1)])
        for a in alloc.analysts:
            w.writerow([a] + [""] * alloc.runs_per_analyst)
    return path


def format_allocation_report(alloc, check, design=None):
    """배정표와 검증 결과를 Markdown 으로 만든다."""
    L = ["# 비교숙련도 사전 배정표", ""]
    L.append(f"- 시험자 {len(alloc.analysts)}명 × 시료 {len(alloc.samples)}종 "
             f"× 반복 {alloc.reps}회 = 1인당 {alloc.runs_per_analyst}개")
    L.append(f"- 총 배정 시편 {len(alloc.rows)}개, 여분 {len(alloc.spares)}개")
    L.append(f"- 난수 시드: `{alloc.seed}` (이 값으로 배정을 언제든 재현할 수 있다)")
    L.append("")
    L.append("> 이 표는 **시험 전에** 확정하고 기록으로 남긴다. "
             "측정 결과를 보고 배정을 바꾸면 시험자 간 편향을 은폐하게 되고 "
             "ISO/IEC 17025 기록 요구사항에도 어긋난다.")
    L.append("")

    L.append("## 배정표")
    L.append("")
    L.append("| 시험자 | " + " | ".join(f"{i}번" for i in range(1, alloc.runs_per_analyst + 1)) + " |")
    L.append("|---" * (alloc.runs_per_analyst + 1) + "|")
    for a in alloc.analysts:
        cells = []
        for pos in range(1, alloc.runs_per_analyst + 1):
            r = next(x for x in alloc.rows if x["시험자"] == a and x["순서"] == pos)
            cells.append(f"{r['시편ID']}")
        L.append(f"| {a} | " + " | ".join(cells) + " |")
    L.append("")

    L.append("## 여분 (재시험용, 배정하지 않음)")
    L.append("")
    L.append("| 시료 | 시편ID |")
    L.append("|---|---|")
    for s in alloc.samples:
        ids = [x["시편ID"] for x in alloc.spares if x["시료"] == s]
        L.append(f"| {s} | {', '.join(ids) if ids else '-'} |")
    L.append("")

    L.append("## 균형 검증")
    L.append("")
    L.append(f"- 완전균형(각 시험자가 각 시료를 {alloc.reps}개씩): "
             f"**{'적합' if check['passed'] else '부적합'}**")
    L.append(f"- 순서 균형 점수: {alloc.imbalance:.2f} "
             f"(0 에 가까울수록 좋음. 시험자 수가 시료 수로 나누어떨어지지 않으면 0 이 될 수 없다)")
    if check["issues"]:
        for i in check["issues"]:
            L.append(f"  - {i}")
    L.append("")
    L.append("| 순서 | " + " | ".join(f"시료 {s}" for s in alloc.samples) + " |")
    L.append("|---" * (len(alloc.samples) + 1) + "|")
    for pos, counts in check["order_table"].items():
        L.append(f"| {pos} | " + " | ".join(str(counts[s]) for s in alloc.samples) + " |")
    L.append("")

    if design:
        L.append("## 사전 설계 검증")
        L.append("")
        L.append("측정 전에 이 설계로 판정이 성립하는지 계산한 결과다. "
                 "시험자 간 편향이 **전혀 없다고 가정**했을 때의 통과율이다.")
        L.append("")
        L.append("| 항목 | 값 |")
        L.append("|---|---|")
        L.append(f"| 가정한 시험자 내 표준편차 σ_w | {design['sigma_within']:.4f} |")
        L.append(f"| 동등성 한계 δ | ±{design['delta']} |")
        L.append(f"| 분산분석 '차이 없음' 비율 | {design['anova_pass']*100:.1f}% |")
        L.append(f"| **동등성 입증 비율** | **{design['tost_pass']*100:.1f}%** |")
        L.append(f"| z-score 전원 만족 비율 | {design['z_pass']*100:.1f}% |")
        L.append("")
        if design["tost_pass"] < 0.5:
            L.append(f"> **경고** 편향이 전혀 없어도 동등성 입증률이 "
                     f"{design['tost_pass']*100:.1f}% 에 불과하다. 이 설계로는 "
                     f"'차이가 없다'를 입증할 수 없다. 반복수를 늘리거나 "
                     f"δ 를 적합성 목적에 맞게 재검토해야 한다.")
            L.append("")
    return "\n".join(L)


def main(argv=None):
    ap = argparse.ArgumentParser(description="비교숙련도 사전 배정기 (모드 A)")
    ap.add_argument("--analysts", required=True,
                    help="시험자 목록. 쉼표로 구분 (예: A,B,C,D,E)")
    ap.add_argument("--samples", default="1,2,3", help="시료 목록. 쉼표로 구분")
    ap.add_argument("--reps", type=int, default=2, help="시료 1개당 반복수")
    ap.add_argument("--spares", type=int, default=2, help="시료당 여분 시편 수")
    ap.add_argument("--seed", type=int, help="난수 시드. 지정하면 배정이 재현된다")
    ap.add_argument("--sigma-within", type=float,
                    help="목표 재현성 (시험자 내 표준편차). 주면 사전 설계 검증을 함께 수행")
    ap.add_argument("--delta", type=float, default=DEFAULT_DELTA, help="동등성 한계")
    ap.add_argument("--alpha", type=float, default=DEFAULT_ALPHA, help="유의수준")
    ap.add_argument("--trials", type=int, default=1000, help="설계 검증 시행 횟수")
    ap.add_argument("--csv-out", help="배정표 CSV 저장 경로")
    ap.add_argument("--template-out", help="빈 결과표 CSV 저장 경로")
    ap.add_argument("-o", "--output", help="배정표 Markdown 저장 경로")
    args = ap.parse_args(argv)

    analysts = [a.strip() for a in args.analysts.split(",") if a.strip()]
    samples = [s.strip() for s in args.samples.split(",") if s.strip()]

    alloc = make_allocation(analysts, samples, reps=args.reps,
                            spares_per_sample=args.spares, seed=args.seed)
    check = check_balance(alloc)

    design = None
    if args.sigma_within is not None:
        design = simulate_design(len(analysts), alloc.runs_per_analyst,
                                 args.sigma_within, bias=0.0, delta=args.delta,
                                 alpha=args.alpha, trials=args.trials)
        design["sigma_within"] = args.sigma_within
        design["delta"] = args.delta

    report = format_allocation_report(alloc, check, design)
    if args.output:
        with open(args.output, "w", encoding="utf-8") as fh:
            fh.write(report + "\n")
        print(f"배정표를 저장했습니다: {args.output}")
    else:
        print(report)

    if args.csv_out:
        print(f"배정 CSV: {write_allocation_csv(alloc, args.csv_out)}")
    if args.template_out:
        print(f"결과 입력 서식: {write_results_template_csv(alloc, args.template_out)}")
    return 0 if check["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())

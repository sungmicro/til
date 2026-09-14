"""CFU 집락수 기반 비교숙련도 통계 코어.

설계 원칙
---------
* 표준 라이브러리만 사용한다. 랩 PC에 numpy/scipy 설치 권한이 없어도 동작해야 한다.
* 모든 검정은 tests/test_cfu_stats.py 에서 scipy 결과와 대조 검증한다.
* 집락수는 Poisson 분포를 따르므로 평균과 분산이 연동된다.
  등분산 가정이 필요한 검정(ANOVA, Levene, TOST)은 반드시 log10 변환 후 수행한다.

참고 규격
---------
* ISO 13528  : 숙련도시험 통계 (Algorithm A 로버스트 추정, 균질성 검정)
* ISO/IEC 17043 : 숙련도시험 운영 (z-score 판정)
* ISO 8199   : 수중 미생물 계수의 일반 요구사항 (계수 유효범위)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

# ---------------------------------------------------------------------------
# 1. 분포 함수 (표준 라이브러리 구현)
# ---------------------------------------------------------------------------

_MAXIT = 300
_EPS = 3.0e-16
_FPMIN = 1.0e-300


def _betacf(a: float, b: float, x: float) -> float:
    """정규화 불완전 베타 함수의 연분수 전개 (Lentz 알고리즘)."""
    qab, qap, qam = a + b, a + 1.0, a - 1.0
    c = 1.0
    d = 1.0 - qab * x / qap
    if abs(d) < _FPMIN:
        d = _FPMIN
    d = 1.0 / d
    h = d
    for m in range(1, _MAXIT + 1):
        m2 = 2 * m
        aa = m * (b - m) * x / ((qam + m2) * (a + m2))
        d = 1.0 + aa * d
        if abs(d) < _FPMIN:
            d = _FPMIN
        c = 1.0 + aa / c
        if abs(c) < _FPMIN:
            c = _FPMIN
        d = 1.0 / d
        h *= d * c
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2))
        d = 1.0 + aa * d
        if abs(d) < _FPMIN:
            d = _FPMIN
        c = 1.0 + aa / c
        if abs(c) < _FPMIN:
            c = _FPMIN
        d = 1.0 / d
        delta = d * c
        h *= delta
        if abs(delta - 1.0) < _EPS:
            break
    return h


def betainc(a: float, b: float, x: float) -> float:
    """정규화 불완전 베타 함수 I_x(a, b)."""
    if x <= 0.0:
        return 0.0
    if x >= 1.0:
        return 1.0
    log_beta = math.lgamma(a + b) - math.lgamma(a) - math.lgamma(b)
    if x < (a + 1.0) / (a + b + 2.0):
        front = math.exp(log_beta + a * math.log(x) + b * math.log1p(-x))
        return front * _betacf(a, b, x) / a
    front = math.exp(log_beta + b * math.log1p(-x) + a * math.log(x))
    return 1.0 - front * _betacf(b, a, 1.0 - x) / b


def f_sf(f: float, df1: float, df2: float) -> float:
    """F 분포 상측 확률 P(F > f)."""
    if f <= 0.0:
        return 1.0
    return betainc(df2 / 2.0, df1 / 2.0, df2 / (df2 + df1 * f))


def t_sf(t: float, df: float) -> float:
    """t 분포 상측 확률 P(T > t)."""
    if df <= 0:
        return float("nan")
    p = 0.5 * betainc(df / 2.0, 0.5, df / (df + t * t))
    return p if t >= 0.0 else 1.0 - p


def t_cdf(t: float, df: float) -> float:
    """t 분포 누적 확률 P(T <= t)."""
    return 1.0 - t_sf(t, df)


def t_ppf(p: float, df: float) -> float:
    """t 분포 분위수. 이분법으로 역산한다 (임계값 표 대체용)."""
    if not 0.0 < p < 1.0:
        raise ValueError("p 는 0 과 1 사이여야 합니다.")
    lo, hi = -1.0e3, 1.0e3
    for _ in range(200):
        mid = (lo + hi) / 2.0
        if t_cdf(mid, df) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


def f_ppf(p: float, df1: float, df2: float) -> float:
    """F 분포 분위수. 이분법으로 역산한다."""
    if not 0.0 < p < 1.0:
        raise ValueError("p 는 0 과 1 사이여야 합니다.")
    lo, hi = 0.0, 1.0e6
    for _ in range(300):
        mid = (lo + hi) / 2.0
        if (1.0 - f_sf(mid, df1, df2)) < p:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0


# ---------------------------------------------------------------------------
# 2. 기술통계
# ---------------------------------------------------------------------------

def mean(xs):
    xs = list(xs)
    if not xs:
        raise ValueError("빈 자료입니다.")
    return math.fsum(xs) / len(xs)


def variance(xs, ddof: int = 1):
    """표본분산 (ddof=1)."""
    xs = list(xs)
    n = len(xs)
    if n - ddof <= 0:
        raise ValueError("자유도가 0 이하입니다.")
    m = mean(xs)
    return math.fsum((x - m) ** 2 for x in xs) / (n - ddof)


def stdev(xs, ddof: int = 1):
    return math.sqrt(variance(xs, ddof))


def median(xs):
    ys = sorted(xs)
    n = len(ys)
    if n == 0:
        raise ValueError("빈 자료입니다.")
    mid = n // 2
    return ys[mid] if n % 2 else (ys[mid - 1] + ys[mid]) / 2.0


def log10_counts(counts):
    """집락수를 log10 으로 변환한다. 0 은 log 를 취할 수 없어 거부한다."""
    out = []
    for c in counts:
        if c is None:
            raise ValueError("결측값이 있습니다.")
        if c <= 0:
            raise ValueError(
                f"집락수 {c} 는 log 변환할 수 없습니다. "
                "불검출(0)은 별도 처리 규칙이 필요합니다."
            )
        out.append(math.log10(float(c)))
    return out


# ---------------------------------------------------------------------------
# 3. 검정
# ---------------------------------------------------------------------------

@dataclass
class TestResult:
    """검정 1건의 결과."""

    name: str
    statistic: float
    p_value: float
    passed: bool
    alpha: float = 0.05
    detail: dict = field(default_factory=dict)

    def verdict(self) -> str:
        return "적합" if self.passed else "부적합"


def anova_oneway(groups, alpha: float = 0.05) -> TestResult:
    """일원배치 분산분석. 귀무가설 = 모든 그룹 평균이 같다.

    passed=True 는 '평균 차이가 발견되지 않았다'는 뜻이며
    '차이가 없음이 입증되었다'는 뜻이 아니다. 동등성 입증은 tost_all_pairs 를 쓸 것.
    """
    groups = [list(g) for g in groups]
    k = len(groups)
    if k < 2:
        raise ValueError("그룹이 2개 이상이어야 합니다.")
    n_total = sum(len(g) for g in groups)
    if n_total - k <= 0:
        raise ValueError("오차 자유도가 0 이하입니다.")

    grand = mean([x for g in groups for x in g])
    ss_between = math.fsum(len(g) * (mean(g) - grand) ** 2 for g in groups)
    ss_within = math.fsum(
        math.fsum((x - mean(g)) ** 2 for x in g) for g in groups
    )
    df1, df2 = k - 1, n_total - k
    ms_between = ss_between / df1
    ms_within = ss_within / df2

    if ms_within == 0.0:
        f_stat = float("inf") if ms_between > 0 else 0.0
        p = 0.0 if ms_between > 0 else 1.0
    else:
        f_stat = ms_between / ms_within
        p = f_sf(f_stat, df1, df2)

    return TestResult(
        name="일원배치 분산분석 (ANOVA)",
        statistic=f_stat,
        p_value=p,
        passed=p > alpha,
        alpha=alpha,
        detail={
            "df_between": df1,
            "df_within": df2,
            "ms_between": ms_between,
            "ms_within": ms_within,
            "group_means": [mean(g) for g in groups],
            "grand_mean": grand,
        },
    )


def levene(groups, center: str = "median", alpha: float = 0.05) -> TestResult:
    """분산 동질성 검정. center='median' 이면 Brown-Forsythe 검정."""
    groups = [list(g) for g in groups]
    k = len(groups)
    if k < 2:
        raise ValueError("그룹이 2개 이상이어야 합니다.")
    locator = median if center == "median" else mean
    z_groups = [[abs(x - locator(g)) for x in g] for g in groups]
    res = anova_oneway(z_groups, alpha=alpha)
    return TestResult(
        name=f"분산 동질성 검정 ({'Brown-Forsythe' if center == 'median' else 'Levene'})",
        statistic=res.statistic,
        p_value=res.p_value,
        passed=res.passed,
        alpha=alpha,
        detail={"group_variances": [variance(g) for g in groups]},
    )


def grubbs(xs, alpha: float = 0.05) -> TestResult:
    """Grubbs 이상치 검정 (양측, 최대 편차 1개).

    passed=True 는 '이상치가 검출되지 않았다'는 뜻이다.
    """
    xs = list(xs)
    n = len(xs)
    if n < 3:
        raise ValueError("Grubbs 검정은 3개 이상 자료가 필요합니다.")
    m = mean(xs)
    s = stdev(xs)
    if s == 0.0:
        return TestResult(
            name="Grubbs 이상치 검정",
            statistic=0.0,
            p_value=1.0,
            passed=True,
            alpha=alpha,
            detail={"index": None, "value": None, "note": "모든 값이 동일합니다."},
        )
    deviations = [abs(x - m) / s for x in xs]
    g = max(deviations)
    idx = deviations.index(g)

    a = g * g * n / ((n - 1) ** 2)
    if a >= 1.0:
        p = 0.0
    else:
        t_sq = a * (n - 2) / (1.0 - a)
        t = math.sqrt(t_sq)
        p = min(1.0, 2.0 * n * t_sf(t, n - 2))

    t_crit = t_ppf(1.0 - alpha / (2.0 * n), n - 2)
    g_crit = ((n - 1) / math.sqrt(n)) * math.sqrt(
        t_crit ** 2 / (n - 2 + t_crit ** 2)
    )

    return TestResult(
        name="Grubbs 이상치 검정",
        statistic=g,
        p_value=p,
        passed=p > alpha,
        alpha=alpha,
        detail={
            "index": idx,
            "value": xs[idx],
            "critical": g_crit,
            "n": n,
        },
    )


def cochran_c(groups, alpha: float = 0.05) -> TestResult:
    """Cochran C 검정. 한 그룹의 분산만 유독 큰지 본다 (ISO 13528 균질성 검정).

    모든 그룹의 반복수가 같아야 한다.
    """
    groups = [list(g) for g in groups]
    k = len(groups)
    sizes = {len(g) for g in groups}
    if len(sizes) != 1:
        raise ValueError("Cochran 검정은 모든 그룹의 반복수가 같아야 합니다.")
    n = sizes.pop()
    if n < 2:
        raise ValueError("그룹당 2개 이상 반복이 필요합니다.")

    variances = [variance(g) for g in groups]
    total = math.fsum(variances)
    if total == 0.0:
        return TestResult(
            name="Cochran C 균질성 검정",
            statistic=0.0,
            p_value=1.0,
            passed=True,
            alpha=alpha,
            detail={"note": "모든 그룹 분산이 0 입니다."},
        )

    c_stat = max(variances) / total
    idx = variances.index(max(variances))
    nu = n - 1

    # C 통계량과 F 분포의 관계로 임계값을 구한다.
    f_crit = f_ppf(1.0 - alpha / k, nu, (k - 1) * nu)
    c_crit = 1.0 / (1.0 + (k - 1) / f_crit)

    # 역방향으로 근사 p-value 를 계산한다.
    if c_stat >= 1.0:
        p = 0.0
    else:
        f_equiv = (k - 1) * c_stat / (1.0 - c_stat)
        p = min(1.0, k * f_sf(f_equiv, nu, (k - 1) * nu))

    return TestResult(
        name="Cochran C 균질성 검정",
        statistic=c_stat,
        p_value=p,
        passed=c_stat <= c_crit,
        alpha=alpha,
        detail={
            "critical": c_crit,
            "index": idx,
            "variances": variances,
            "k": k,
            "n": n,
        },
    )


def tost_pair(
    group_a,
    group_b,
    delta: float,
    ms_within: float,
    df_within: int,
    alpha: float = 0.05,
):
    """두 그룹의 동등성 검정 (TOST). 반환값은 (p_value, 평균차).

    ANOVA 의 오차평균제곱(ms_within)과 오차자유도를 공유해 검정력을 높인다.
    """
    a, b = list(group_a), list(group_b)
    diff = mean(a) - mean(b)
    se = math.sqrt(ms_within * (1.0 / len(a) + 1.0 / len(b)))
    if se == 0.0:
        return (0.0 if abs(diff) < delta else 1.0), diff
    p_lower = t_sf((diff + delta) / se, df_within)
    p_upper = t_cdf((diff - delta) / se, df_within)
    return max(p_lower, p_upper), diff


def tost_all_pairs(groups, delta: float, alpha: float = 0.05) -> TestResult:
    """모든 쌍의 동등성 검정. '차이가 없다'를 실제로 입증하는 검정이다.

    교집합-합집합 검정(IUT)이므로 다중비교 보정이 필요 없다.
    모든 쌍이 동등해야 전체가 동등하므로, 쌍별 p 중 최댓값으로 판정한다.

    delta 는 동등성 한계(log10 단위). 절차서에 규정이 없으면 0.25 를 쓴다.
    """
    groups = [list(g) for g in groups]
    k = len(groups)
    if k < 2:
        raise ValueError("그룹이 2개 이상이어야 합니다.")

    anova = anova_oneway(groups, alpha=alpha)
    ms_within = anova.detail["ms_within"]
    df_within = anova.detail["df_within"]

    pairs = []
    worst_p = 0.0
    for i in range(k):
        for j in range(i + 1, k):
            p, diff = tost_pair(
                groups[i], groups[j], delta, ms_within, df_within, alpha
            )
            pairs.append({"i": i, "j": j, "p_value": p, "diff": diff})
            worst_p = max(worst_p, p)

    worst = max(pairs, key=lambda d: d["p_value"])
    return TestResult(
        name=f"동등성 검정 (TOST, ±{delta} log10)",
        statistic=max(abs(d["diff"]) for d in pairs),
        p_value=worst_p,
        passed=worst_p < alpha,
        alpha=alpha,
        detail={
            "delta": delta,
            "pairs": pairs,
            "worst_pair": (worst["i"], worst["j"]),
            "max_abs_diff": max(abs(d["diff"]) for d in pairs),
        },
    )


# ---------------------------------------------------------------------------
# 4. 로버스트 추정과 z-score (ISO 13528)
# ---------------------------------------------------------------------------

def algorithm_a(xs, max_iter: int = 50, tol: float = 1e-10):
    """ISO 13528 부속서 C 의 Algorithm A. 로버스트 평균과 표준편차를 반환한다.

    이상치를 제거하지 않고 영향만 축소하므로, 자료를 버리지 않아도 된다.
    """
    xs = list(xs)
    p = len(xs)
    if p < 3:
        raise ValueError("Algorithm A 는 3개 이상 자료가 필요합니다.")

    x_star = median(xs)
    s_star = 1.483 * median([abs(x - x_star) for x in xs])

    for _ in range(max_iter):
        if s_star == 0.0:
            break
        delta = 1.5 * s_star
        winsorized = [min(max(x, x_star - delta), x_star + delta) for x in xs]
        new_x = mean(winsorized)
        new_s = 1.134 * math.sqrt(
            math.fsum((w - new_x) ** 2 for w in winsorized) / (p - 1)
        )
        if abs(new_x - x_star) < tol and abs(new_s - s_star) < tol:
            x_star, s_star = new_x, new_s
            break
        x_star, s_star = new_x, new_s

    return x_star, s_star


def z_scores(values, assigned=None, sigma=None):
    """ISO/IEC 17043 z-score. 기준값이 없으면 Algorithm A 로 추정한다.

    판정: |z| <= 2 만족, 2 < |z| < 3 경고, |z| >= 3 부적합.
    """
    values = list(values)
    if assigned is None or sigma is None:
        est_x, est_s = algorithm_a(values)
        assigned = est_x if assigned is None else assigned
        sigma = est_s if sigma is None else sigma

    out = []
    for v in values:
        z = float("nan") if sigma == 0 else (v - assigned) / sigma
        if math.isnan(z):
            flag = "판정불가"
        elif abs(z) < 2.0:
            flag = "만족"
        elif abs(z) < 3.0:
            flag = "경고"
        else:
            flag = "부적합"
        out.append({"value": v, "z": z, "flag": flag})
    return {"assigned": assigned, "sigma": sigma, "scores": out}

"""cfu_stats 의 표준 라이브러리 구현을 scipy 와 대조 검증한다.

scipy 가 없는 환경(랩 PC)에서는 scipy 대조 테스트만 건너뛰고 나머지는 실행된다.
"""

import math
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import cfu_stats as cs  # noqa: E402

try:
    import scipy.stats as sps
    import scipy.special as ssp

    HAS_SCIPY = True
except ImportError:  # pragma: no cover
    HAS_SCIPY = False

needs_scipy = unittest.skipUnless(HAS_SCIPY, "scipy 미설치 환경")

# 작년 형태를 흉내낸 예시 자료 (5명 x 6개, log10 변환 전 집락수)
FIVE_ANALYSTS = [
    [220, 230, 156, 178, 201, 188],
    [212, 245, 163, 190, 209, 175],
    [198, 221, 149, 182, 195, 203],
    [230, 238, 171, 166, 215, 192],
    [205, 226, 158, 174, 199, 186],
]


class TestDistributions(unittest.TestCase):
    @needs_scipy
    def test_betainc_matches_scipy(self):
        for a in (0.5, 1.0, 2.5, 10.0):
            for b in (0.5, 1.0, 3.0, 25.0):
                for x in (0.01, 0.2, 0.5, 0.77, 0.99):
                    self.assertAlmostEqual(
                        cs.betainc(a, b, x), float(ssp.betainc(a, b, x)), places=12
                    )

    @needs_scipy
    def test_f_sf_matches_scipy(self):
        for df1, df2 in ((1, 1), (4, 25), (2, 10), (5, 100)):
            for f in (0.1, 0.5, 1.0, 2.5, 7.3, 40.0):
                self.assertAlmostEqual(
                    cs.f_sf(f, df1, df2), float(sps.f.sf(f, df1, df2)), places=12
                )

    @needs_scipy
    def test_t_sf_matches_scipy(self):
        for df in (1, 3, 10, 28, 120):
            for t in (-4.0, -1.2, 0.0, 0.7, 2.5, 6.0):
                self.assertAlmostEqual(
                    cs.t_sf(t, df), float(sps.t.sf(t, df)), places=12
                )

    @needs_scipy
    def test_ppf_roundtrip(self):
        for df in (3, 12, 60):
            for p in (0.9, 0.95, 0.975, 0.995):
                self.assertAlmostEqual(
                    cs.t_ppf(p, df), float(sps.t.ppf(p, df)), places=8
                )
        for df1, df2 in ((4, 25), (1, 4)):
            for p in (0.9, 0.95, 0.99):
                self.assertAlmostEqual(
                    cs.f_ppf(p, df1, df2), float(sps.f.ppf(p, df1, df2)), places=6
                )


class TestAnova(unittest.TestCase):
    @needs_scipy
    def test_anova_matches_scipy(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        got = cs.anova_oneway(groups)
        want_f, want_p = sps.f_oneway(*groups)
        self.assertAlmostEqual(got.statistic, float(want_f), places=10)
        self.assertAlmostEqual(got.p_value, float(want_p), places=12)

    @needs_scipy
    def test_anova_with_an_outlier(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        groups[2] = cs.log10_counts([198, 221, 149, 182, 195, 45])
        got = cs.anova_oneway(groups)
        want_f, want_p = sps.f_oneway(*groups)
        self.assertAlmostEqual(got.statistic, float(want_f), places=10)
        self.assertAlmostEqual(got.p_value, float(want_p), places=12)

    def test_identical_groups_give_f_zero(self):
        g = [1.0, 2.0, 3.0]
        got = cs.anova_oneway([g, list(g), list(g)])
        self.assertAlmostEqual(got.statistic, 0.0, places=12)
        self.assertTrue(got.passed)


class TestLevene(unittest.TestCase):
    @needs_scipy
    def test_levene_matches_scipy(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        got = cs.levene(groups, center="median")
        want_w, want_p = sps.levene(*groups, center="median")
        self.assertAlmostEqual(got.statistic, float(want_w), places=10)
        self.assertAlmostEqual(got.p_value, float(want_p), places=12)

    @needs_scipy
    def test_levene_mean_center_matches_scipy(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        got = cs.levene(groups, center="mean")
        want_w, want_p = sps.levene(*groups, center="mean")
        self.assertAlmostEqual(got.statistic, float(want_w), places=10)
        self.assertAlmostEqual(got.p_value, float(want_p), places=12)


class TestGrubbs(unittest.TestCase):
    # 공개된 Grubbs 양측 임계값표 (alpha=0.05)
    KNOWN_CRITICAL = {3: 1.1543, 4: 1.4812, 5: 1.7150, 10: 2.2900, 20: 2.7090}

    def test_critical_values_match_published_table(self):
        # 표 값은 문헌마다 마지막 자리 반올림이 다르므로 허용오차 0.002 로 본다.
        for n, expected in self.KNOWN_CRITICAL.items():
            xs = list(range(n))
            got = cs.grubbs(xs).detail["critical"]
            self.assertAlmostEqual(got, expected, delta=0.002, msg=f"n={n}")

    @needs_scipy
    def test_critical_value_matches_exact_formula(self):
        """표 반올림과 무관하게 정확 공식과 일치하는지 본다."""
        for n in (3, 5, 8, 20, 40):
            t = float(sps.t.ppf(1 - 0.05 / (2 * n), n - 2))
            exact = ((n - 1) / math.sqrt(n)) * math.sqrt(t ** 2 / (n - 2 + t ** 2))
            got = cs.grubbs(list(range(n))).detail["critical"]
            self.assertAlmostEqual(got, exact, places=6, msg=f"n={n}")

    def test_detects_planted_outlier(self):
        xs = [2.30, 2.36, 2.19, 2.25, 2.31, 2.28, 2.33, 1.10]
        res = cs.grubbs(xs)
        self.assertFalse(res.passed)
        self.assertEqual(res.detail["value"], 1.10)

    def test_clean_data_passes(self):
        xs = [2.30, 2.36, 2.19, 2.25, 2.31, 2.28, 2.33, 2.22]
        self.assertTrue(cs.grubbs(xs).passed)

    def test_p_value_consistent_with_critical(self):
        # 임계값 바로 위/아래에서 판정과 p-value 가 일치해야 한다.
        xs = [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 20.0]
        res = cs.grubbs(xs)
        self.assertEqual(res.passed, res.p_value > res.alpha)
        self.assertEqual(res.passed, res.statistic <= res.detail["critical"])


class TestCochran(unittest.TestCase):
    # Cochran 공개 임계값표 (alpha=0.05). 키는 (그룹수 k, 자유도 nu=n-1).
    KNOWN_CRITICAL = {
        (3, 1): 0.9669,
        (3, 2): 0.8709,
        (3, 3): 0.7977,
        (5, 1): 0.8413,
        (5, 2): 0.6838,
        (5, 3): 0.5981,
    }

    def test_critical_values_match_published_table(self):
        for (k, nu), expected in self.KNOWN_CRITICAL.items():
            reps = nu + 1
            groups = [[0.0] * (reps - 1) + [float(i + 1)] for i in range(k)]
            got = cs.cochran_c(groups).detail["critical"]
            self.assertAlmostEqual(got, expected, delta=0.001, msg=f"k={k} nu={nu}")

    def test_flags_one_wildly_variable_group(self):
        groups = [[2.30, 2.31], [2.28, 2.29], [2.25, 2.26], [2.30, 2.32], [1.50, 2.90]]
        res = cs.cochran_c(groups)
        self.assertFalse(res.passed)
        self.assertEqual(res.detail["index"], 4)

    def test_homogeneous_groups_pass(self):
        groups = [[2.30, 2.31], [2.28, 2.30], [2.25, 2.27], [2.30, 2.32], [2.29, 2.27]]
        self.assertTrue(cs.cochran_c(groups).passed)

    def test_rejects_unequal_replicates(self):
        with self.assertRaises(ValueError):
            cs.cochran_c([[1.0, 2.0], [1.0, 2.0, 3.0]])


class TestTost(unittest.TestCase):
    @needs_scipy
    def test_pairwise_tost_matches_manual_scipy(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        delta = 0.25
        anova = cs.anova_oneway(groups)
        mse = anova.detail["ms_within"]
        dfe = anova.detail["df_within"]

        a, b = groups[0], groups[3]
        got_p, got_diff = cs.tost_pair(a, b, delta, mse, dfe)

        diff = float(sum(a) / len(a) - sum(b) / len(b))
        se = math.sqrt(mse * (1 / len(a) + 1 / len(b)))
        want = max(
            float(sps.t.sf((diff + delta) / se, dfe)),
            float(sps.t.cdf((diff - delta) / se, dfe)),
        )
        self.assertAlmostEqual(got_p, want, places=12)
        self.assertAlmostEqual(got_diff, diff, places=12)

    def test_tight_data_is_equivalent(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        res = cs.tost_all_pairs(groups, delta=0.25)
        self.assertTrue(res.passed)

    def test_shifted_group_breaks_equivalence(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        groups[1] = [v + 0.9 for v in groups[1]]
        res = cs.tost_all_pairs(groups, delta=0.25)
        self.assertFalse(res.passed)
        self.assertIn(1, res.detail["worst_pair"])

    def test_narrow_delta_is_harder_to_pass(self):
        groups = [cs.log10_counts(g) for g in FIVE_ANALYSTS]
        wide = cs.tost_all_pairs(groups, delta=0.50).p_value
        narrow = cs.tost_all_pairs(groups, delta=0.05).p_value
        self.assertLess(wide, narrow)


class TestRobust(unittest.TestCase):
    def test_algorithm_a_resists_an_outlier(self):
        clean = [2.30, 2.36, 2.19, 2.25, 2.31]
        dirty = clean[:-1] + [9.90]
        x_clean, _ = cs.algorithm_a(clean)
        x_dirty, _ = cs.algorithm_a(dirty)
        # 산술평균은 크게 흔들리지만 로버스트 평균은 거의 움직이지 않아야 한다.
        self.assertGreater(abs(cs.mean(dirty) - cs.mean(clean)), 1.0)
        self.assertLess(abs(x_dirty - x_clean), 0.15)

    def test_algorithm_a_on_symmetric_data_equals_mean(self):
        xs = [1.0, 2.0, 3.0, 4.0, 5.0]
        x_star, _ = cs.algorithm_a(xs)
        self.assertAlmostEqual(x_star, 3.0, places=6)

    def test_z_score_flags(self):
        res = cs.z_scores([10.0, 10.1, 9.9, 10.05, 30.0])
        flags = [s["flag"] for s in res["scores"]]
        self.assertEqual(flags[-1], "부적합")
        self.assertTrue(all(f == "만족" for f in flags[:-1]))


class TestLogTransform(unittest.TestCase):
    def test_rejects_zero_and_negative(self):
        with self.assertRaises(ValueError):
            cs.log10_counts([100, 0])
        with self.assertRaises(ValueError):
            cs.log10_counts([100, -3])

    def test_rejects_missing(self):
        with self.assertRaises(ValueError):
            cs.log10_counts([100, None])

    def test_values(self):
        self.assertAlmostEqual(cs.log10_counts([100])[0], 2.0, places=12)


if __name__ == "__main__":
    unittest.main(verbosity=2)

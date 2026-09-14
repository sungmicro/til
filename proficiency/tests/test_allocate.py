"""사전 배정기의 균형 조건과 설계 검증을 검사한다."""

import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, ROOT)

import allocate as al  # noqa: E402
import judge  # noqa: E402

ANALYSTS = ["A", "B", "C", "D", "E"]
SAMPLES = ["1", "2", "3"]


class TestBalance(unittest.TestCase):
    def test_balance_holds_across_many_seeds(self):
        for seed in range(30):
            a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=2,
                                   seed=seed)
            chk = al.check_balance(a)
            self.assertTrue(chk["passed"], f"seed={seed}: {chk['issues']}")

    def test_每_analyst_gets_every_sample_equally(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=1)
        for name in ANALYSTS:
            for s in SAMPLES:
                n = sum(1 for r in a.rows if r["시험자"] == name and r["시료"] == s)
                self.assertEqual(n, 2, f"{name}/{s}")

    def test_no_specimen_assigned_twice(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=3, seed=7)
        ids = [r["시편ID"] for r in a.rows]
        self.assertEqual(len(ids), len(set(ids)))

    def test_spares_never_overlap_assignments(self):
        for seed in range(20):
            a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=2, seed=seed)
            assigned = {r["시편ID"] for r in a.rows}
            spare = {s["시편ID"] for s in a.spares}
            self.assertEqual(assigned & spare, set(), f"seed={seed}")

    def test_spare_count(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=4, seed=3)
        self.assertEqual(len(a.spares), 4 * len(SAMPLES))
        self.assertEqual(len(a.rows), len(ANALYSTS) * len(SAMPLES) * 2)

    def test_perfect_balance_when_divisible(self):
        """시험자 수가 시료 수로 나누어떨어지면 순서 균형 점수가 0 이어야 한다."""
        a = al.make_allocation(["A", "B", "C", "D", "E", "F"], SAMPLES,
                               reps=2, seed=5)
        self.assertAlmostEqual(a.imbalance, 0.0, places=9)

    def test_balance_holds_for_every_configuration(self):
        """시험자 수, 시료 수, 반복수를 넓게 바꿔가며 균형이 항상 성립해야 한다.

        회전 구성은 시험자 수가 주기의 배수일 때만 균형을 보장한다.
        순환 라틴 구성으로 바꾼 이유가 이 테스트다.
        """
        for k in range(2, 10):
            for ns in range(1, 5):
                for reps in range(1, 4):
                    for seed in range(6):
                        a = al.make_allocation(
                            [chr(65 + i) for i in range(k)],
                            [str(i + 1) for i in range(ns)],
                            reps=reps, spares_per_sample=1, seed=seed)
                        chk = al.check_balance(a)
                        self.assertTrue(
                            chk["passed"],
                            f"k={k} 시료={ns} 반복={reps} seed={seed}: {chk['issues']}")

    def test_imbalance_hits_theoretical_minimum(self):
        """5명/3시료면 순서마다 {1,2,2} 가 최선이고 그때 점수는 4.0 이다."""
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=11)
        self.assertAlmostEqual(a.imbalance, 4.0, places=9)


class TestReproducibility(unittest.TestCase):
    def test_same_seed_gives_same_allocation(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=2, seed=99)
        b = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=2, seed=99)
        self.assertEqual(a.rows, b.rows)
        self.assertEqual(a.spares, b.spares)

    def test_different_seed_gives_different_allocation(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=1)
        b = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=2)
        self.assertNotEqual(a.rows, b.rows)

    def test_seed_is_recorded(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=None)
        b = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=a.seed)
        self.assertEqual(a.rows, b.rows)


class TestValidation(unittest.TestCase):
    def test_rejects_bad_inputs(self):
        with self.assertRaises(ValueError):
            al.make_allocation(ANALYSTS, SAMPLES, reps=0)
        with self.assertRaises(ValueError):
            al.make_allocation(ANALYSTS, [], reps=2)
        with self.assertRaises(ValueError):
            al.make_allocation(["A"], SAMPLES, reps=2)

    def test_check_balance_catches_tampering(self):
        """배정을 손으로 고치면 검증에서 걸려야 한다."""
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=4)
        current = a.rows[0]["시료"]
        a.rows[0]["시료"] = next(s for s in SAMPLES if s != current)
        self.assertFalse(al.check_balance(a)["passed"])


class TestDesignSimulation(unittest.TestCase):
    def test_no_bias_gives_nominal_type_one_error(self):
        """편향이 없으면 ANOVA 통과율이 1-alpha 근처여야 한다."""
        r = al.simulate_design(5, 6, 0.2, bias=0.0, alpha=0.05, trials=800)
        self.assertGreater(r["anova_pass"], 0.90)
        self.assertLess(r["anova_pass"], 0.99)

    def test_large_bias_is_detected(self):
        r = al.simulate_design(5, 6, 0.1, bias=0.6, alpha=0.05, trials=400)
        self.assertLess(r["anova_pass"], 0.20)

    def test_tost_impossible_when_sigma_exceeds_delta(self):
        """산포가 동등성 한계보다 크면 편향이 없어도 입증할 수 없다."""
        r = al.simulate_design(5, 6, 0.2835, bias=0.0, delta=0.25, trials=400)
        self.assertEqual(r["tost_pass"], 0.0)

    def test_more_reps_improve_equivalence(self):
        small = al.simulate_design(5, 6, 0.14, delta=0.25, trials=400)["tost_pass"]
        large = al.simulate_design(5, 16, 0.14, delta=0.25, trials=400)["tost_pass"]
        self.assertGreater(large, small)

    def test_recommend_reps_is_reachable_for_tight_data(self):
        rec = al.recommend_reps(5, 0.14, delta=0.25, target=0.80, max_reps=20, trials=300)
        self.assertTrue(rec["achieved"])
        self.assertGreater(rec["reps"], 6)

    def test_attainable_delta_grows_with_sigma(self):
        tight = al.attainable_delta(5, 6, 0.14, trials=300)
        loose = al.attainable_delta(5, 6, 0.2835, trials=300)
        self.assertTrue(tight["achieved"] and loose["achieved"])
        self.assertGreater(loose["delta"], tight["delta"])


class TestOutputs(unittest.TestCase):
    def test_results_template_is_readable_by_judge(self):
        """빈 결과표에 값을 채우면 판정기가 바로 읽을 수 있어야 한다."""
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=8)
        d = tempfile.mkdtemp()
        path = al.write_results_template_csv(a, os.path.join(d, "t.csv"))

        with open(path, encoding="utf-8-sig") as fh:
            lines = [l.strip() for l in fh if l.strip()]
        filled = [lines[0]] + [
            f"{name}," + ",".join(str(0.1 * (i + j)) for j in range(6))
            for i, name in enumerate(ANALYSTS)
        ]
        filled_path = os.path.join(d, "filled.csv")
        with open(filled_path, "w", encoding="utf-8") as fh:
            fh.write("\n".join(filled) + "\n")

        names, groups = judge.read_csv(filled_path)
        self.assertEqual(names, ANALYSTS)
        self.assertTrue(all(len(g) == 6 for g in groups))

    def test_allocation_csv_has_every_row(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, spares_per_sample=2, seed=6)
        path = al.write_allocation_csv(a, os.path.join(tempfile.mkdtemp(), "a.csv"))
        with open(path, encoding="utf-8-sig") as fh:
            lines = [l for l in fh.read().splitlines() if l.strip()]
        self.assertEqual(len(lines), len(a.rows) + 1)

    def test_report_warns_when_design_underpowered(self):
        a = al.make_allocation(ANALYSTS, SAMPLES, reps=2, seed=2)
        design = al.simulate_design(5, 6, 0.2835, delta=0.25, trials=200)
        design.update(sigma_within=0.2835, delta=0.25)
        text = al.format_allocation_report(a, al.check_balance(a), design)
        self.assertIn("경고", text)
        self.assertIn("시험 전에", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)

"""모드 B 판정기의 입출력과 판정 결과를 검증한다."""

import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.join(HERE, "..")
sys.path.insert(0, ROOT)

import judge  # noqa: E402

SAMPLES = os.path.join(ROOT, "samples")


def write_csv(text):
    fh = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
    fh.write(text)
    fh.close()
    return fh.name


class TestReadCsv(unittest.TestCase):
    def test_numeric_column_header_is_not_read_as_data(self):
        """열 이름이 1,2,3 처럼 숫자여도 헤더로 인식해야 한다."""
        path = write_csv("분석자,1,2,3\nA,1,2,3\nB,4,5,6\n")
        names, groups = judge.read_csv(path)
        self.assertEqual(names, ["A", "B"])
        self.assertEqual(groups, [[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]])

    def test_text_column_header(self):
        path = write_csv("이름,측정1,측정2\nA,1,2\nB,3,4\n")
        names, groups = judge.read_csv(path)
        self.assertEqual(names, ["A", "B"])
        self.assertEqual(len(groups[0]), 2)

    def test_no_header_row(self):
        path = write_csv("A,1,2,3\nB,4,5,6\n")
        names, _ = judge.read_csv(path)
        self.assertEqual(names, ["A", "B"])

    def test_blank_lines_ignored(self):
        path = write_csv("분석자,1,2\n\nA,1,2\n\nB,3,4\n\n")
        names, _ = judge.read_csv(path)
        self.assertEqual(names, ["A", "B"])

    def test_rejects_ragged_rows(self):
        path = write_csv("분석자,1,2,3\nA,1,2,3\nB,4,5\n")
        with self.assertRaises(ValueError):
            judge.read_csv(path)

    def test_rejects_single_measurement_per_analyst(self):
        """1인당 1개면 그룹 내 변동을 못 구하므로 명확히 거부해야 한다."""
        path = write_csv("분석자,R\nA,0.1\nB,0.2\nC,0.3\n")
        with self.assertRaises(ValueError) as ctx:
            judge.read_csv(path)
        self.assertIn("분산분석", str(ctx.exception))

    def test_rejects_empty_file(self):
        path = write_csv("분석자,1,2\n")
        with self.assertRaises(ValueError):
            judge.read_csv(path)

    def test_reads_real_sample_files(self):
        for fname in ("antibacterial_R_ecoli.csv", "antibacterial_R_saureus.csv"):
            names, groups = judge.read_csv(os.path.join(SAMPLES, fname))
            self.assertEqual(names, ["A", "B", "C", "D", "E"], fname)
            self.assertTrue(all(len(g) == 6 for g in groups), fname)


class TestPrepare(unittest.TestCase):
    def test_r_input_is_not_transformed(self):
        """R 은 이미 log 단위다. 다시 log 를 취하면 안 된다."""
        groups, unit = judge.prepare([[-0.14, 0.28]], "r")
        self.assertEqual(groups, [[-0.14, 0.28]])
        self.assertIn("R", unit)

    def test_cfu_input_is_log_transformed(self):
        groups, unit = judge.prepare([[100, 1000]], "cfu")
        self.assertAlmostEqual(groups[0][0], 2.0, places=12)
        self.assertAlmostEqual(groups[0][1], 3.0, places=12)
        self.assertIn("log10", unit)

    def test_negative_r_would_break_cfu_mode(self):
        """음수 R 을 cfu 모드로 잘못 넣으면 조용히 통과하지 않고 실패해야 한다."""
        with self.assertRaises(ValueError):
            judge.prepare([[-0.14, 0.28]], "cfu")


class TestCountRange(unittest.TestCase):
    def test_flags_out_of_range_counts(self):
        warns = judge.count_range_warnings([[25, 150], [200, 350]], ["A", "B"])
        self.assertEqual(len(warns), 2)
        self.assertEqual(warns[0], ("A", [25]))
        self.assertEqual(warns[1], ("B", [350]))

    def test_in_range_counts_are_silent(self):
        self.assertEqual(judge.count_range_warnings([[30, 300], [150, 200]], ["A", "B"]), [])


class TestAnalyzeRealData(unittest.TestCase):
    """작년 실제 자료로 판정 결과를 고정한다 (회귀 테스트)."""

    def _run(self, fname):
        names, groups = judge.read_csv(os.path.join(SAMPLES, fname))
        return judge.analyze(names, groups, input_type="r", trials=2000)

    def test_ecoli(self):
        res = self._run("antibacterial_R_ecoli.csv")
        self.assertAlmostEqual(res["anova"].p_value, 0.01371, places=5)
        self.assertAlmostEqual(res["levene"].p_value, 0.72706, places=5)
        self.assertAlmostEqual(res["tost"].p_value, 0.61317, places=5)
        self.assertFalse(res["anova"].passed)      # 평균 차이 탐지됨
        self.assertTrue(res["levene"].passed)      # 산포는 동일
        self.assertFalse(res["tost"].passed)       # 동등성 입증 실패
        self.assertFalse(res["classic_pass"])
        # 이상치 검정으로는 아무도 제외할 수 없다.
        self.assertTrue(res["grubbs_all"].passed)
        self.assertTrue(res["grubbs_means"].passed)
        # z-score 로는 전원 만족이다.
        self.assertTrue(all(s["flag"] == "만족" for s in res["z"]["scores"]))

    def test_saureus(self):
        res = self._run("antibacterial_R_saureus.csv")
        self.assertAlmostEqual(res["anova"].p_value, 0.04024, places=5)
        self.assertAlmostEqual(res["levene"].p_value, 0.92735, places=5)
        self.assertFalse(res["classic_pass"])
        self.assertTrue(res["grubbs_all"].passed)
        self.assertTrue(res["grubbs_means"].passed)
        self.assertTrue(all(s["flag"] == "만족" for s in res["z"]["scores"]))
        # D 의 평균이 가장 낮아야 한다.
        self.assertEqual(res["means"].index(min(res["means"])), 3)

    def test_random_reallocation_rate_is_high(self):
        """산포 자체는 좋아서 무작위 배정이면 대부분 통과한다."""
        for fname in ("antibacterial_R_ecoli.csv", "antibacterial_R_saureus.csv"):
            names, groups = judge.read_csv(os.path.join(SAMPLES, fname))
            res = judge.analyze(names, groups, input_type="r", trials=5000)
            self.assertGreater(res["random_rate"], 0.80, fname)
            self.assertFalse(res["classic_pass"], fname)

    def test_reallocation_rate_is_deterministic(self):
        names, groups = judge.read_csv(os.path.join(SAMPLES, "antibacterial_R_ecoli.csv"))
        a = judge.analyze(names, groups, input_type="r", trials=3000)["random_rate"]
        b = judge.analyze(names, groups, input_type="r", trials=3000)["random_rate"]
        self.assertEqual(a, b)


class TestReport(unittest.TestCase):
    def test_report_has_all_sections(self):
        names, groups = judge.read_csv(os.path.join(SAMPLES, "antibacterial_R_ecoli.csv"))
        text = judge.format_report(judge.analyze(names, groups, input_type="r", trials=1000))
        for section in ("분석자별 요약", "숙련도 판정", "보조 검정",
                        "이상치 검정", "무작위 재배정 통과율"):
            self.assertIn(section, text)
        self.assertIn("체계적 편향이 실재한다", text)

    def test_cfu_report_shows_range_warning(self):
        names = ["A", "B", "C"]
        groups = [[220, 230, 156], [178, 201, 188], [12, 195, 203]]
        text = judge.format_report(judge.analyze(names, groups, input_type="cfu", trials=500))
        self.assertIn("계수 유효범위", text)
        self.assertIn("12", text)


class TestCli(unittest.TestCase):
    def test_cli_writes_report_file(self):
        out = os.path.join(tempfile.mkdtemp(), "report.md")
        rc = judge.main([
            os.path.join(SAMPLES, "antibacterial_R_ecoli.csv"),
            "--type", "r", "--trials", "500", "-o", out,
        ])
        self.assertEqual(rc, 0)
        with open(out, encoding="utf-8") as fh:
            self.assertIn("비교숙련도 판정 보고서", fh.read())


if __name__ == "__main__":
    unittest.main(verbosity=2)

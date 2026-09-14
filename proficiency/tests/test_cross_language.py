"""R 구현과 Python 구현이 같은 값을 내는지 대조한다.

두 언어로 독립 구현해 서로 검증한다. R 이 없는 환경에서는 건너뛴다.
"""

import json
import os
import shutil
import subprocess
import sys
import unittest

HERE = os.path.dirname(__file__)
ROOT = os.path.abspath(os.path.join(HERE, ".."))
sys.path.insert(0, ROOT)

import judge  # noqa: E402

RSCRIPT = shutil.which("Rscript")
needs_r = unittest.skipUnless(RSCRIPT, "R 미설치 환경")

R_DRIVER = r"""
source("proficiency.R")
args <- commandArgs(trailingOnly = TRUE)
d <- read_results(args[1])
r <- analyze_proficiency(d, input_type = args[2], delta = as.numeric(args[3]), trials = 1)
cat(sprintf(
  '{"levene_stat":%.12g,"levene_p":%.12g,"anova_f":%.12g,"anova_p":%.12g,%s}',
  r$levene$statistic, r$levene$p.value,
  r$anova[["F-값"]][1], r$anova_p,
  sprintf('"tost_p":%.12g,"grubbs_g":%.12g,"grubbs_crit":%.12g,"z":[%s],"assigned":%.12g,"sigma":%.12g',
          r$tost$p.value, r$grubbs_all$statistic, r$grubbs_all$critical,
          paste(sprintf("%.12g", r$z$z), collapse = ","),
          r$z$assigned, r$z$sigma)))
"""


def run_r(csv_path, input_type="r", delta=0.25):
    driver = os.path.join(ROOT, "R", "_cross_check.R")
    with open(driver, "w", encoding="utf-8") as fh:
        fh.write(R_DRIVER)
    try:
        env = dict(os.environ, LC_ALL="C.UTF-8")
        proc = subprocess.run(
            [RSCRIPT, "_cross_check.R", os.path.abspath(csv_path), input_type, str(delta)],
            cwd=os.path.join(ROOT, "R"), capture_output=True, text=True, env=env, check=True,
        )
        return json.loads(proc.stdout.strip())
    finally:
        if os.path.exists(driver):
            os.remove(driver)


@needs_r
class TestCrossLanguage(unittest.TestCase):
    """같은 자료에 대해 R 과 Python 이 같은 통계량을 내야 한다."""

    def _compare(self, csv_name, input_type="r"):
        path = os.path.join(ROOT, "samples", csv_name)
        r = run_r(path, input_type)
        names, groups = judge.read_csv(path)
        py = judge.analyze(names, groups, input_type=input_type, trials=1)

        self.assertAlmostEqual(r["levene_stat"], py["levene"].statistic, places=10)
        self.assertAlmostEqual(r["levene_p"], py["levene"].p_value, places=10)
        self.assertAlmostEqual(r["anova_f"], py["anova"].statistic, places=10)
        self.assertAlmostEqual(r["anova_p"], py["anova"].p_value, places=10)
        self.assertAlmostEqual(r["tost_p"], py["tost"].p_value, places=10)
        self.assertAlmostEqual(r["grubbs_g"], py["grubbs_all"].statistic, places=10)
        self.assertAlmostEqual(r["grubbs_crit"], py["grubbs_all"].detail["critical"], places=6)
        self.assertAlmostEqual(r["assigned"], py["z"]["assigned"], places=10)
        self.assertAlmostEqual(r["sigma"], py["z"]["sigma"], places=10)
        for rz, pz in zip(r["z"], py["z"]["scores"]):
            self.assertAlmostEqual(rz, pz["z"], places=10)

    def test_ecoli(self):
        self._compare("antibacterial_R_ecoli.csv")

    def test_saureus(self):
        self._compare("antibacterial_R_saureus.csv")


if __name__ == "__main__":
    unittest.main(verbosity=2)

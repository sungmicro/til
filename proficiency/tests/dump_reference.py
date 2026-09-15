"""judge.py 의 analyze() 결과를 JSON 으로 떨군다. JS 구현 대조용 기준값이다."""

import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import judge  # noqa: E402  (경로를 넣은 뒤에 불러와야 한다)


def r(x):
    """결과 객체를 JSON 으로 만들 수 있는 형태로 편다."""
    if hasattr(x, "statistic"):
        return {
            "statistic": x.statistic,
            "pValue": x.p_value,
            "passed": bool(x.passed),
            "detail": getattr(x, "detail", None),
        }
    return x


def main():
    fixtures = json.loads((HERE / "fixture.json").read_text())
    out = {}
    for key, fx in fixtures.items():
        # 무작위 재배정은 RNG 가 언어마다 달라 값이 일치할 수 없다.
        # 여기서는 결정적인 통계만 기준으로 삼고 trials 는 최소로 둔다.
        res = judge.analyze(
            fx["names"], fx["groups"],
            input_type=fx["input_type"], delta=fx["delta"],
            alpha=fx["alpha"], trials=1,
        )
        out[key] = {
            "unit": res["unit"],
            "n_per_analyst": res["n_per_analyst"],
            "means": res["means"],
            "stdevs": res["stdevs"],
            "levene": r(res["levene"]),
            "anova": r(res["anova"]),
            "tost": r(res["tost"]),
            "grubbs_all": r(res["grubbs_all"]),
            "grubbs_all_owner": res["grubbs_all_owner"],
            "grubbs_means": r(res["grubbs_means"]),
            "z": {
                "assigned": res["z"]["assigned"],
                "sigma": res["z"]["sigma"],
                "scores": [
                    {"value": s["value"], "z": s["z"], "flag": s["flag"]}
                    for s in res["z"]["scores"]
                ],
            },
            "classic_pass": bool(res["classic_pass"]),
            "count_warnings": [[n, b] for n, b in res["count_warnings"]],
        }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=2, default=float)


if __name__ == "__main__":
    main()

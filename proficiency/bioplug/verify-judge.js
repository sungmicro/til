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

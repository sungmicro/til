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

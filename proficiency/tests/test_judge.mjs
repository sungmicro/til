/* verify-judge.js 가 judge.py 와 같은 값을 내는지 대조한다.
 *
 * 무작위 재배정 통과율은 난수 발생기가 언어마다 달라 값이 일치할 수 없다.
 * 그래서 결정적인 통계만 엄격히 대조하고, 재배정 통과율은 범위와 재현성만 본다.
 */
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';

const require = createRequire(import.meta.url);
const HERE = path.dirname(new URL(import.meta.url).pathname);
// 기본은 저장소 안의 원본. 설치된 사본을 보려면 PUB 로 가리킨다.
const PUB = process.env.PUB || path.join(HERE, '..', 'bioplug');

require(path.join(PUB, 'verify-stats.js'));
require(path.join(PUB, 'verify-judge.js'));

const J = globalThis.ProfJudge;
const fixtures = JSON.parse(readFileSync(path.join(HERE, 'fixture.json'), 'utf8'));
const reference = JSON.parse(readFileSync(path.join(HERE, 'reference.json'), 'utf8'));

let failed = 0;
function check(name, ok, detail) {
  if (ok) return;
  failed++;
  console.error('FAIL  ' + name + (detail ? '  — ' + detail : ''));
}
function near(name, got, want, tol = 1e-12) {
  const ok = Number.isFinite(got) && Number.isFinite(want)
    && Math.abs(got - want) <= tol * Math.max(1, Math.abs(want));
  check(name, ok, `got ${got}, want ${want}`);
}
function eq(name, got, want) {
  check(name, got === want, `got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`);
}

// --- 1. judge.py 와의 수치 대조 ------------------------------------------------

for (const key of Object.keys(fixtures)) {
  const fx = fixtures[key];
  const want = reference[key];
  const got = J.analyze(fx.names, fx.groups, {
    inputType: fx.input_type, delta: fx.delta, alpha: fx.alpha, trials: 200,
  });
  const T = (s) => `[${key}] ${s}`;

  eq(T('unit'), got.unit, want.unit);
  eq(T('nPerAnalyst'), got.nPerAnalyst, want.n_per_analyst);
  want.means.forEach((m, i) => near(T(`means[${i}]`), got.means[i], m));
  want.stdevs.forEach((s, i) => near(T(`stdevs[${i}]`), got.stdevs[i], s));

  for (const [jsKey, pyKey] of [['levene', 'levene'], ['anova', 'anova'], ['tost', 'tost'],
                                ['grubbsAll', 'grubbs_all'], ['grubbsMeans', 'grubbs_means']]) {
    near(T(`${jsKey}.statistic`), got[jsKey].statistic, want[pyKey].statistic);
    near(T(`${jsKey}.pValue`), got[jsKey].pValue, want[pyKey].pValue, 1e-9);
    eq(T(`${jsKey}.passed`), got[jsKey].passed, want[pyKey].passed);
  }

  eq(T('grubbsAllOwner'), got.grubbsAllOwner, want.grubbs_all_owner);
  near(T('z.assigned'), got.z.assigned, want.z.assigned);
  near(T('z.sigma'), got.z.sigma, want.z.sigma);
  want.z.scores.forEach((s, i) => {
    near(T(`z.scores[${i}].z`), got.z.scores[i].z, s.z);
    eq(T(`z.scores[${i}].flag`), got.z.scores[i].flag, s.flag);
  });
  eq(T('classicPass'), got.classicPass, want.classic_pass);

  eq(T('countWarnings.length'), got.countWarnings.length, want.count_warnings.length);
  want.count_warnings.forEach(([name, vals], i) => {
    eq(T(`countWarnings[${i}].name`), got.countWarnings[i].name, name);
    eq(T(`countWarnings[${i}].values`), JSON.stringify(got.countWarnings[i].values),
       JSON.stringify(vals));
  });

  check(T('randomRate 범위'), got.randomRate >= 0 && got.randomRate <= 1, String(got.randomRate));
}

// 같은 시드면 재배정 통과율도 같아야 한다 (기록 재현성).
{
  const fx = fixtures.r;
  const opts = { inputType: 'r', delta: 0.25, alpha: 0.05, trials: 500, seed: 20260914 };
  const a = J.analyze(fx.names, fx.groups, opts).randomRate;
  const b = J.analyze(fx.names, fx.groups, opts).randomRate;
  eq('randomRate 재현성', a, b);
}

// --- 2. 숫자 읽기 --------------------------------------------------------------

{
  const p = J.parseNumbers('1\n2\n3');
  eq('parse 엔터', JSON.stringify(p.values), '[1,2,3]');
  eq('parse 엔터 invalid', p.invalid.length, 0);
}
{
  const p = J.parseNumbers(' -0.14 \r\n-0.12\r\n\n0.06\t0.12, 3e-2 ');
  eq('parse 혼합 구분자', JSON.stringify(p.values), '[-0.14,-0.12,0.06,0.12,0.03]');
}
{
  const p = J.parseNumbers('12\nabc\n7');
  eq('parse 잡음 값', JSON.stringify(p.values), '[12,7]');
  eq('parse 잡음 보고', JSON.stringify(p.invalid), '["abc"]');
}
{
  const p = J.parseNumbers('   \n  \n');
  eq('parse 빈 입력', JSON.stringify(p.values), '[]');
}

// --- 3. 입력 검증 --------------------------------------------------------------

eq('검증: 개수 불일치',
   J.validate([[1, 2, 3], [1, 2]]),
   '시험자마다 측정값 개수가 다릅니다: 2, 3');
eq('검증: 1개뿐',
   J.validate([[1], [2]]),
   '시험자당 측정값이 1개뿐이면 시험자 내 변동을 추정할 수 없어 분산분석이 성립하지 않습니다.');
eq('검증: 시험자 1명',
   J.validate([[1, 2, 3]]),
   '시험자가 2명 이상이어야 비교할 수 있습니다.');
eq('검증: 통과', J.validate([[1, 2, 3], [4, 5, 6]]), null);

// CFU 는 log 를 취하므로 0 이하가 있으면 안 된다.
check('검증: CFU 0 이하', (() => {
  try { J.analyze(['A', 'B'], [[10, 0], [5, 5]], { inputType: 'cfu' }); return false; }
  catch (e) { return /0 이하/.test(e.message); }
})(), '0 이하 CFU 를 걸러내지 않았다');

// --- 결과 ---------------------------------------------------------------------

if (failed) {
  console.error(`\n${failed}건 실패`);
  process.exit(1);
}
console.log('통과 — judge.py 와 일치');

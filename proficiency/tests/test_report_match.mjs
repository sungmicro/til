/* 화면이 만든 Markdown 보고서와 judge.py 가 만든 보고서를 줄 단위로 대조한다.
 * 무작위 재배정 통과율은 난수가 언어마다 달라 값이 일치할 수 없으므로 그 줄만 뺀다.
 */
import { loadPlaywright } from './_playwright.mjs';
import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const { chromium } = loadPlaywright();

const HERE = path.dirname(new URL(import.meta.url).pathname);
const ROOT = path.join(HERE, '..');          // proficiency/
const JUDGE = path.join(ROOT, 'judge.py');
const fx = JSON.parse(readFileSync(path.join(HERE, 'fixture.json'), 'utf8')).r;

// judge.py 가 읽을 CSV 를 만든다.
const csv = ['분석자,1,2,3,4,5,6']
  .concat(fx.names.map((n, i) => [n].concat(fx.groups[i]).join(',')))
  .join('\n');
writeFileSync(path.join(HERE, 'roundtrip.csv'), csv);

const pyReport = execFileSync('python3',
  [JUDGE, path.join(HERE, 'roundtrip.csv'), '--type', 'r',
   '--delta', String(fx.delta), '--alpha', String(fx.alpha), '--trials', '2000'],
  { cwd: ROOT, encoding: 'utf8' });

const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto((process.env.BASE || 'http://localhost:8931') +
                (process.env.PAGE || '/verify.html'));
await page.fill('#pw', 'bioplug2026');
await page.click('#gateForm button[type=submit]');
await page.waitForSelector('#app:not(.hidden)');
await page.click('#tabB');
for (let i = 0; i < fx.groups.length; i++) {
  await page.locator('#jBoxes .box textarea').nth(i).fill(fx.groups[i].join('\n'));
}
await page.click('#jRun');
await page.waitForSelector('#jReportSection:not(.hidden)', { timeout: 10000 });
const jsReport = await page.textContent('#jReport');
await browser.close();

/* 대조에서 뺄 줄: 난수에 기대는 통과율, 생성일.
 *
 * 그리고 일부러 다르게 둔 표현을 맞춘다. 숫자가 같은지를 보려는 것이므로
 * 아래 셋은 정규화한다.
 *   - 화면은 모드 A 와 맞춰 "시험자", judge.py 는 "분석자" 를 쓴다
 *   - 검정 이름은 verify-stats.js 와 cfu_stats.py 가 원래 조금 다르다
 */
const drop = (s) => s.split('\n')
  .filter((l) => !/통과율:|생성일:|^> /.test(l))
  .map((l) => l.trimEnd()
    .replace(/분석자/g, '시험자')
    .replace(/일원배치 분산분석 \(ANOVA\)/g, '일원배치 분산분석')
    .replace(/동등성 검정 \(TOST,[^)]*\)/g, '동등성 검정 (TOST)'))
  .filter((l) => l !== '')
  .join('\n');

const a = drop(jsReport), b = drop(pyReport);
if (a === b) {
  console.log('보고서 일치 — 화면과 judge.py 가 같은 값을 낸다');
  process.exit(0);
}
const al = a.split('\n'), bl = b.split('\n');
console.error('보고서 불일치:');
for (let i = 0; i < Math.max(al.length, bl.length); i++) {
  if (al[i] !== bl[i]) console.error(`  ${i}\n    화면: ${al[i]}\n    파이썬: ${bl[i]}`);
}
process.exit(1);

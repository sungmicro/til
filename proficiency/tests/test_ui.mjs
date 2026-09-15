/* 검증 탭 모드 B 의 브라우저 동작을 확인한다.
 * 잠금 해제 → 모드 전환 → 값 입력 → 판정 → 오류 입력 → 좁은 화면 순으로 본다.
 */
import { loadPlaywright } from './_playwright.mjs';

const { chromium } = loadPlaywright();

const URL_BASE = process.env.BASE || 'http://localhost:8931';
// 단일 파일 배포물(verify-standalone.html)도 같은 검사를 통과해야 한다.
const PAGE = process.env.PAGE || '/verify.html';
const PW = 'bioplug2026';

let failed = 0;
function check(name, ok, detail) {
  if (ok) { console.log('  ok   ' + name); return; }
  failed++;
  console.error('  FAIL ' + name + (detail ? '  — ' + detail : ''));
}

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });

const consoleErrors = [];
page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
page.on('pageerror', (e) => consoleErrors.push('pageerror: ' + e.message));

await page.goto(URL_BASE + PAGE);

// --- 잠금 ---------------------------------------------------------------------
check('잠금 화면이 먼저 뜬다', await page.locator('#gate').isVisible());
check('앱은 잠겨 있다', !(await page.locator('#app').isVisible()));

await page.fill('#pw', '틀린비밀번호');
await page.click('#gateForm button[type=submit]');
await page.waitForTimeout(150);
check('틀린 비밀번호는 막힌다', !(await page.locator('#app').isVisible()));

await page.fill('#pw', PW);
await page.click('#gateForm button[type=submit]');
await page.waitForSelector('#app:not(.hidden)', { timeout: 3000 });
check('맞는 비밀번호로 열린다', await page.locator('#app').isVisible());

// --- 모드 전환 ----------------------------------------------------------------
check('처음에는 모드 A', await page.locator('#modeA').isVisible() && !(await page.locator('#modeB').isVisible()));
await page.click('#tabB');
check('모드 B 로 전환된다', await page.locator('#modeB').isVisible() && !(await page.locator('#modeA').isVisible()));

// --- 조건과 기대 개수 ----------------------------------------------------------
const note = await page.textContent('#jNeedNote');
check('기대 개수 안내 (시료3 × 페트리2 = 6)', /1인당 측정값 6개/.test(note.replace(/\s+/g, ' ')), note);
check('시험자 칸이 5개 생긴다', (await page.locator('#jBoxes .box').count()) === 5);

await page.selectOption('#jSamples', '5');
check('시료 5개로 바꾸면 10개',
  /1인당 측정값 10개/.test((await page.textContent('#jNeedNote')).replace(/\s+/g, ' ')));
await page.selectOption('#jSamples', '3');

// --- 붙여넣기 입력 -------------------------------------------------------------
const paste = ['-0.14', '-0.12', '-0.04', '-0.06', '0.06', '0.12'].join('\n');
await page.locator('#jBoxes .box textarea').first().fill(paste);
await page.waitForTimeout(100);
check('엔터로 구분한 6개를 인식한다',
  /^6 \/ 6개$/.test((await page.locator('#jBoxes .count').first().textContent()).trim()),
  await page.locator('#jBoxes .count').first().textContent());

// 개수가 모자라면 그 칸만 걸린다
await page.locator('#jBoxes .box textarea').nth(1).fill('1\n2\n3');
await page.waitForTimeout(100);
check('모자란 칸은 bad 로 표시된다',
  (await page.locator('#jBoxes .count').nth(1).getAttribute('class')).includes('bad'));

await page.click('#jRun');
await page.waitForTimeout(150);
check('개수가 안 맞으면 판정이 막힌다', await page.locator('#jMsg').isVisible());
check('어느 시험자가 문제인지 알려준다',
  /B: 3개 \(기대 6개\)/.test(await page.textContent('#jMsg')), await page.textContent('#jMsg'));

// 숫자가 아닌 값
await page.locator('#jBoxes .box textarea').nth(1).fill('1\n2\n삼\n4\n5\n6');
await page.waitForTimeout(100);
await page.click('#jRun');
await page.waitForTimeout(150);
check('숫자가 아닌 값을 잡아낸다', /숫자가 아닌 값/.test(await page.textContent('#jMsg')));

// --- 예시 값으로 판정 ----------------------------------------------------------
await page.click('#jDemo');
await page.waitForTimeout(150);
const counts = await page.locator('#jBoxes .count').allTextContents();
check('예시 값이 전 칸에 6개씩 들어간다', counts.every((c) => /^6 \/ 6개$/.test(c.trim())), counts.join(' | '));

await page.click('#jRun');
await page.waitForSelector('#jResults:not(.hidden)', { timeout: 10000 });
check('판정 결과가 나온다', await page.locator('#jResults').isVisible());
check('오류 메시지는 사라진다', !(await page.locator('#jMsg').isVisible()));

const res = await page.textContent('#jResults');
for (const [label, re] of [
  ['시험자별 요약', /시험자별 요약/],
  ['z-score 열', /z-score/],
  ['숙련도 판정', /숙련도 판정/],
  ['Levene', /분산 동질성 검정/],
  ['분산분석', /일원배치 분산분석/],
  ['TOST', /동등성 검정/],
  ['Grubbs', /이상치 검정/],
  ['무작위 재배정 통과율', /무작위 재배정 통과율/],
  ['시행 횟수 표기', /100,000회 시행/],
]) check('결과에 ' + label + ' 이 있다', re.test(res));

check('시험자 5명이 표에 다 나온다',
  (await page.locator('#jResults table').first().locator('tr').count()) === 6);

// --- 보고서 -------------------------------------------------------------------
check('Markdown 보고서가 나온다', await page.locator('#jReportSection').isVisible());
const md = await page.textContent('#jReport');
check('보고서가 제목으로 시작한다', md.startsWith('# 비교숙련도 판정 보고서'), md.slice(0, 40));
check('보고서에 5개 절이 있다', (md.match(/^## /gm) || []).length === 5,
  String((md.match(/^## /gm) || []).length));

// --- CFU 경로 -----------------------------------------------------------------
await page.selectOption('#jUnit', 'cfu');
const cfuRows = [[182, 168, 201, 174, 190, 165], [143, 151, 138, 160, 147, 155],
                 [210, 198, 225, 187, 203, 216], [176, 169, 181, 172, 195, 158],
                 [28, 305, 199, 188, 177, 192]];
for (let i = 0; i < cfuRows.length; i++) {
  await page.locator('#jBoxes .box textarea').nth(i).fill(cfuRows[i].join('\n'));
}
await page.click('#jRun');
await page.waitForTimeout(1500);
const cfuRes = await page.textContent('#jResults');
check('CFU 계수 유효범위 이탈을 경고한다', /계수 유효범위\(30~300\) 이탈/.test(cfuRes));
check('경고에 해당 값이 찍힌다', /28, 305/.test(cfuRes), cfuRes.slice(0, 160));

// CFU 0 은 log 를 못 취하므로 막혀야 한다
await page.locator('#jBoxes .box textarea').first().fill('0\n168\n201\n174\n190\n165');
await page.click('#jRun');
await page.waitForTimeout(300);
check('CFU 0 이하를 막는다', /0 이하일 수 없습니다/.test(await page.textContent('#jMsg')));

// --- 좁은 화면 ----------------------------------------------------------------
await page.setViewportSize({ width: 390, height: 800 });
await page.waitForTimeout(200);
const overflow = await page.evaluate(() =>
  document.documentElement.scrollWidth - document.documentElement.clientWidth);
check('390px 에서 가로 스크롤이 없다', overflow <= 0, 'overflow ' + overflow + 'px');

// --- 모드 A 배정표 -------------------------------------------------------------
await page.setViewportSize({ width: 1200, height: 900 });
await page.click('#tabA');
await page.selectOption('#unit', 'cfu');
await page.click('#btnDemo');
await page.click('#btnRun');
await page.waitForSelector('#results:not(.hidden)', { timeout: 10000 });

const allocCell = page.locator('#results table').nth(1).locator('tr').nth(1).locator('td').first();
// textContent 는 두 노드를 붙여 읽으므로 ID 와 값을 따로 꺼낸다.
const shown = (await allocCell.locator('.cellval').textContent()).trim();
const idText = (await allocCell.textContent()).trim().replace(shown, '').trim();

check('배정표 셀에 시편 ID 가 있다', /^S\d+-\d+$/.test(idText), idText);
check('배정표 셀에 스크리닝 값이 함께 나온다', /^\d+(\.\d+)?$/.test(shown), shown);
check('값이 ID 와 분리된 줄로 나온다', (await allocCell.locator('.cellval').count()) === 1);
check('값이 실제로 아래 줄에 그려진다', await allocCell.locator('.cellval').evaluate(
  (el) => getComputedStyle(el).display === 'block'));

// 배정표에 찍힌 값은 실제로 입력한 스크리닝 값이어야 한다 (엉뚱한 숫자가 아니어야 한다)
const entered = await page.evaluate(() =>
  Array.from(document.querySelectorAll('#inputTable input')).map((el) => el.value));
check('배정표의 값이 실제 입력값이다', entered.includes(shown), shown + ' 은 입력값에 없다');

// --- 콘솔 --------------------------------------------------------------------
check('콘솔 오류가 없다', consoleErrors.length === 0, consoleErrors.join(' | '));

await browser.close();
if (failed) { console.error(`\n${failed}건 실패`); process.exit(1); }
console.log('\nUI 통과');

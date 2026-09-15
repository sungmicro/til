/* Playwright 를 찾는다.
 *
 * 전역 설치, 프로젝트 설치, npx 캐시 어디에 있어도 쓰도록 한다.
 * PLAYWRIGHT_PATH 로 직접 가리킬 수도 있다.
 */
import { createRequire } from 'node:module';
import { existsSync, readdirSync } from 'node:fs';
import path from 'node:path';
import os from 'node:os';

function candidates() {
  const out = [];
  if (process.env.PLAYWRIGHT_PATH) out.push(process.env.PLAYWRIGHT_PATH);
  out.push(import.meta.url);
  for (const base of ['/usr/local/lib/node_modules/', '/opt/homebrew/lib/node_modules/']) {
    if (existsSync(base)) out.push(base);
  }
  const npx = path.join(os.homedir(), '.npm', '_npx');
  if (existsSync(npx)) {
    for (const dir of readdirSync(npx)) {
      const mod = path.join(npx, dir, 'node_modules');
      if (existsSync(path.join(mod, 'playwright'))) out.push(mod + '/');
    }
  }
  return out;
}

export function loadPlaywright() {
  const tried = [];
  for (const from of candidates()) {
    try {
      return createRequire(from)('playwright');
    } catch (e) {
      tried.push(from);
    }
  }
  console.error('Playwright 를 찾지 못했습니다. 아래를 확인하세요.\n' +
    '  npx playwright install chromium\n' +
    '또는 PLAYWRIGHT_PATH 로 설치 위치를 지정하세요.\n' +
    '찾아본 곳:\n  ' + tried.join('\n  '));
  process.exit(1);
}

# bio-plug 「검증」 탭

모드가 둘이다. 의존성 없는 정적 파일 4개이며 빌드 단계가 필요 없다.

- **A · 시험 전 설계** — 배정표를 만들고, 이 설계로 판정이 성립하는지 확인한다
- **B · 시험 후 판정** — 측정값을 넣으면 숙련도를 판정한다. R 없이 끝난다

| 파일 | 내용 |
|---|---|
| `verify.html` | 페이지 (비밀번호 게이트 + 화면) |
| `verify-stats.js` | 통계 구현. Python·R 구현과 대조 검증됨 |
| `verify-judge.js` | 모드 B 판정 코어. `judge.py` 와 같은 값을 낸다 |
| `verify-app.js` | 배정·검증·R 코드 생성·화면 연결 |

## 설치 — 한 줄

`install-verify.sh` 를 받아서 실행하면 끝난다. 파일 내용이 스크립트 안에 들어 있어
따로 내려받을 것이 없다.

```bash
bash install-verify.sh              # ~/bioplug/public 에 설치
bash install-verify.sh ~/경로/bioplug  # 다른 위치
```

하는 일은 이렇다.

- `public/` 에 네 파일을 쓴다 (기존 파일이 있으면 타임스탬프를 붙여 백업)
- 다시 설치할 수 있도록 `tools/install-verify.sh` 에 자기 사본을 둔다
- `build.mjs` 가 `public/` 을 지우는지 검사해서, 그렇다면 `postbuild` 설정을 안내한다
- 나머지 파일은 건드리지 않는다

빌드가 `public/` 을 비운다면 `package.json` 에 한 줄을 넣어 자동 복구시킨다.

```json
"postbuild": "bash tools/install-verify.sh ."
```

설치 후 확인과 배포:

```bash
cd ~/bioplug/public && python3 -m http.server 8000   # http://localhost:8000/verify.html
cd ~/bioplug && node build.mjs && npx vercel --prod --yes   # https://bioplug.vercel.app/verify
```

탭 링크는 `build.mjs` 의 `tabsHTML()` 이 `public/verify.html` 유무를 보고 넣는다.
따로 손댈 것이 없다.

### 파일 하나로 쓰고 싶다면

`verify-standalone.html` 은 JS 를 심어 넣은 단일 파일이다. `public/` 에 복사만 하면 된다.
`verify.html` 과 기능이 같다.

### 원본과 배포물

`install-verify.sh` 와 `verify-standalone.html` 은 **자동 생성 파일**이다.
직접 고치지 말고 원본 네 파일을 고친 뒤 다시 만든다.

```bash
python3 build-installer.py
```

`tests/test_bioplug_build.py` 가 배포물이 원본과 어긋나지 않는지 검사한다.

## 비밀번호

기본값은 `bioplug2026` 이다. 바꾸려면 브라우저 콘솔에서 해시를 만들어
`verify-app.js` 의 `PW_HASH` 를 교체한다.

```js
crypto.subtle.digest('SHA-256', new TextEncoder().encode('새비밀번호'))
  .then(b => console.log([...new Uint8Array(b)].map(x => x.toString(16).padStart(2,'0')).join('')))
```

**이것은 실제 접근 통제가 아니다.** 확인이 브라우저에서만 이루어지므로 페이지 소스를
보면 우회할 수 있다. 동료가 실수로 들어오는 것을 막는 용도로만 쓰고, 정말 막아야 하는
자료라면 서버 쪽 인증이 필요하다. 페이지에는 `noindex` 를 넣어 검색 노출은 막아두었다.

## 쓰는 순서 — 모드 A (시험 전)

1. **설계** — 시험자 수, 시료 종수, 반복수, 여분, 입력 단위, δ, 시드를 고른다.
2. **스크리닝 값 입력** — 각 시편을 본 시험 전에 1회 측정한 값. 엑셀에서 붙여넣기가 된다.
3. **검증 및 배정 생성**
   - Grubbs 로 이상치 시편을 판정해 여분으로 교체한다
   - Cochran 으로 로트 간 균질성을 확인한다
   - 순환 라틴 구성으로 균형 배정을 만든다
   - 이 설계로 판정이 성립하는지 몬테카를로로 계산한다
   - 배정표 칸에는 시편 ID 와 그 시편의 스크리닝 값이 함께 찍힌다
4. **R 코드 내려받기** — 측정이 끝나면 `results` 의 `NA` 를 채우고 실행하면 보고서가 나온다.

## 쓰는 순서 — 모드 B (시험 후)

R 을 돌리지 않고 화면에서 판정까지 끝내려면 이쪽을 쓴다.

1. **조건** — 시험자 수(3~5), 시료 수(3~5), 시료당 페트리 수(1~3), 단위, δ, α.
   시험자 1인당 기대 개수는 시료 × 페트리 다. 시료 3 × 페트리 2 면 6개다.
2. **측정값 입력** — 시험자별 칸에 숫자만 붙여넣는다. 엔터로 구분하면 되고 공백·쉼표·탭도 된다.
   칸마다 인식된 개수가 실시간으로 뜨고, 기대 개수와 다르면 그 칸이 걸린다.

   시험자별로 칸을 나눈 이유가 있다. 한 칸에 전부 넣으면 숫자 하나가 빠졌을 때
   그 뒤 전원의 값이 한 칸씩 밀리는데, 결과는 오류 없이 그럴듯하게 나온다.
3. **판정하기** — 시험자별 z-score, 보조 검정(Levene·ANOVA·TOST), Grubbs,
   무작위 재배정 통과율 진단, Markdown 보고서가 나온다.

판정 통계는 `judge.py` 와 같다. 값이 일치하는지는 `tests/test_judge.mjs` 와
`tests/test_report_match.mjs` 가 검사한다.

## 하지 않는 것

측정이 끝난 값에 담당자를 맞춰 끼워 p 값을 통과시키는 탐색은 넣지 않았다.
작년 자료 기준으로 무작위 배정의 90~92% 가 이미 현행 기준을 통과하므로 그런 조합을
찾기는 쉽지만, 그렇게 통과시키면 실재하는 시험자 간 편향을 은폐하게 되고 실제 수행자와
다른 담당자가 기재된 기록이 남는다.

대신 같은 목적을 정당하게 푸는 두 가지를 넣었다.

- **이상치 시편 교체** — Grubbs 라는 사전에 정한 기준으로만 제외한다. 여분의 정당한 용도다.
- **사전 설계 검증** — 시험 전에 "이 설계로 판정이 성립하는가"를 계산한다.

## 검증

`verify-stats.js` 는 Python(`cfu_stats.py`), R(`R/proficiency.R`) 구현과
소수 10자리까지 일치한다. `tests/test_cross_language.py` 가 이를 검사한다.
페이지가 만들어내는 R 코드도 실제로 실행해 같은 값이 나오는 것을 확인했다.

모드 B 는 `judge.py` 와 대조한다.

```bash
node tests/test_judge.mjs          # 판정 값이 judge.py 와 같은지

cd bioplug && python3 -m http.server 8931 &
node tests/test_ui.mjs             # 브라우저 동작 (Playwright)
node tests/test_report_match.mjs   # 화면이 만든 보고서 = judge.py 보고서
```

`test_ui.mjs` 는 `PAGE=/verify-standalone.html` 로 단일 파일 배포물도 같은 검사를 돌린다.
`BASE=https://bioplug.vercel.app PAGE=/verify` 로 배포본을 볼 수도 있다.

무작위 재배정 통과율은 난수 발생기가 언어마다 달라 값이 일치할 수 없다.
그래서 결정적인 통계만 엄격히 대조하고, 통과율은 범위와 재현성만 본다.

`reference.json` 은 `tests/dump_reference.py` 로 다시 뽑는다. 파이썬 쪽 통계를
고쳤으면 다시 뽑아야 한다.

브라우저 동작은 Chromium 으로 확인했다 (잠금, 모드 전환, 입력표 생성, 붙여넣기,
개수 불일치·비숫자 입력 차단, 결측 경고, 배정 중복 없음, R 코드 생성,
CFU 계수 유효범위 경고, CFU 0 차단, 390px 폭에서 가로 스크롤 없음).

---
name: uniscan-pc-agent-ui
overview: PC Agent(.NET Framework 4.8 WinForms) UI를 “모바일 앱 느낌”으로 2탭(Device/Settings) 구성으로 정리합니다.
---

## 0) 결론(스킨/렌더링 방식)
- **선택: 2) Gsemac.Forms.Styles 스킨 적용 + 표준 WinForms 레이아웃으로 구성**
  - 1) `OnPaint`로 HTML/Flutter처럼 전체를 직접 드로잉: **가능은 하지만** (히트테스트/포커스/접근성/스크롤/리사이즈/유지보수) 비용이 커서 이번 범위에선 비추
  - 2) **`TableLayoutPanel`/`FlowLayoutPanel`로 Row/Column 레이아웃 구현** + Gsemac 스킨으로 통일감(폰트/컬러) 적용: 가장 단순/안정

## 1) 공통 UI 가이드(필수)
- **폰트**: 전 영역 **Arial**, 색상은 “아주 짙은 흑색” 우선
  - `FontFamily=Arial`
  - 기본 텍스트: `#111111` (또는 `Color.FromArgb(17,17,17)`)
  - 보조 텍스트: `#333333`
  - 비활성/설명: `#666666`
- **배경**: 흰색 바탕
  - 배경: `#FFFFFF`
  - 카드/구분선: `#F2F2F2`, `#E6E6E6`
- **레이아웃**: “모바일” 느낌
  - 기본 패딩: 12~16px
  - 섹션 간격: 12px
  - 카드 라운드: 10px (가능하면)

## 2) 화면 구조(하단 탭 2개)
- 메인 폼은 상단 타이틀바 + 컨텐츠 + **하단 탭바(2개)** 형태
- 탭 구성
  - **Tab #1: Device**
  - **Tab #2: Settings** (현재 “로그 화면”은 여기로 이동)

구현 방식(권장)
- `TabControl` + `Alignment=Bottom` + `Dock=Fill`
- 탭 내부는 `TableLayoutPanel`로 Row/Column 구성

## 3) Device 탭(1번탭)
### 3-1) 상단(크게)
- **DeviceId(=pcId)** 를 큰 글씨로 표시
- 그 아래 **QR 코드** 표시(정사각)
  - QR 페이로드(권장): `pairingCode` 또는 `pairingCode + pcId` (앱에서 스캔/입력 편의)
  - 예: `uniscan://pair?code=123456&pcId=group:device:machine`

### 3-2) 중단/하단(상태)
- **연결 상태**: connected/disconnected + 마지막 연결 시간
- **바코드 수신 상태**
  - last received barcode (마스킹 옵션)
  - queue length
  - last input result (ok/fail) + agentAttempt + duration
- **전역 입력(에뮬레이션) 상태**
  - target window 매칭 결과(있으면)
  - input method: scancode/unicode/clipboard

## 4) Settings 탭(2번탭)
### 4-1) 설정(모바일 Row/Column 형태)
- `serverUrl`
- `group`, `deviceName`, `machineId` (**machineId는 Windows `MachineGuid` 기반으로 자동 결정/고정**)
- `targetWindow.processName`
- `targetWindow.windowTitleContains`
- `barcodeSuffixKey` (Enter/Tab)
- (선택) “시작 시 트레이”, “윈도우 시작 시 자동 실행”

### 4-2) 로그(기존 UI 이동)
- 현재 ListBox 로그는 Settings 탭 하단 영역으로 이동
- 로그는 최근 N줄만 유지(예: 250)
- “복사”, “지우기” 버튼 제공(필요 시)

## 5) QR 생성 NuGet(가벼운 것 선택)
- 목표: **QR 생성만**(리더/스캐너 불필요), 의존성 최소
- 후보(구현 시 비교 후 확정)
  - `Net.Codecrete.QrCodeGenerator` 계열(순수 생성 중심)
  - `QRCoder`(대중적이지만 상대적으로 의존/용량 증가 가능)
- 출력은 `Bitmap`으로 만들어 `PictureBox`에 표시

## 6) 스킨 적용(“안 먹는” 문제 해결 지침)
- 적용 원칙: **컨트롤 생성이 끝난 뒤**(탭/패널 포함) `UserPaintStyleApplicator.ApplyStyles(form)` 1회 호출
- 폼/탭 페이지/패널별로 필요하면 재적용(단, 중복 호출은 최소화)
- 현재 요구는 “흰 배경”이므로 CSS는 `WhiteUI.css`로 별도 제공(다크는 옵션)


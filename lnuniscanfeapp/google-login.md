## Google 로그인(회원가입) 연동 가이드 — lunarsystem.co.kr

목표
- **메일 송수신은 기존 lunarsystem.co.kr(Worksmobile) 그대로 사용**합니다. 구글 이메일 연동은 사용하지 않습니다.
- **회원가입/로그인만 Google 계정(OAuth2, OpenID Connect)으로 연동**합니다.

### 1) 사전 준비(도메인/사이트)
- **HTTPS 준비**: 운영 서비스는 `https://lunarsystem.co.kr` 또는 서브도메인(예: `https://uniscan.lunarsystem.co.kr`)에 TLS 적용
- **개인정보 처리방침 / 이용약관 페이지**: 공개 URL 준비
  - 예: `https://lunarsystem.co.kr/privacy`, `https://lunarsystem.co.kr/terms`
- **도메인 소유권 검증(구글)**: Google Search Console 또는 Google Cloud의 Domain verification로 `lunarsystem.co.kr` 검증
  - 권장: DNS TXT 방식 (안정적이며 UI 변경에도 영향 적음)
- **robots.txt**: 기본 허용 및 Sitemap 공개(권장)
  - 경로: `https://lunarsystem.co.kr/robots.txt`
- **리디렉션 엔드포인트(서버/클라이언트)** 준비
  - 서버 콜백(권장): `https://lunarsystem.co.kr/auth/google/callback`
  - 로컬 개발 시 서버 콜백 예시: `http://127.0.0.1:58001/auth/google/callback` (API가 58001에서 구동 시)
  - 프런트엔드가 코드 교환까지 담당한다면 FE 콜백: `http://localhost:58000/auth/google/callback`

참고(로컬 개발 환경)
- 프런트엔드: `http://localhost:58000` 또는 `http://127.0.0.1:58000`
- API(디버깅): `http://127.0.0.1:58001` (json-server 등)

### 2) Google Cloud Console 설정
1. 프로젝트 생성
   - 콘솔: `https://console.cloud.google.com`
   - 새 프로젝트 생성 또는 기존 프로젝트 선택
2. OAuth 동의화면 구성
   - 사용자 유형: 내부(Workspace) 또는 외부
   - 앱 이름, 사용자 지원 이메일, 개발자 연락처 이메일 입력
   - **승인된 도메인**에 `lunarsystem.co.kr` 추가
   - 개인정보처리방침/이용약관 URL 등록
   - 범위(Scopes): 최소 `openid`, `email`, `profile` (Gmail API 등 메일 관련 스코프 불필요)
   - 테스트 단계에서는 테스트 사용자 지정 → 운영 전환 시 “프로덕션”으로 게시
3. OAuth 클라이언트 ID 생성(유형: Web application)
   - Authorized JavaScript origins
     - 운영: `https://lunarsystem.co.kr` (또는 사용 서브도메인)
     - 로컬: `http://localhost:58000`, `http://127.0.0.1:58000`
   - Authorized redirect URIs
     - 서버 콜백(권장): `https://lunarsystem.co.kr/auth/google/callback`
     - 로컬 서버 콜백(예): `http://127.0.0.1:58001/auth/google/callback`
     - FE 콜백(선택): `http://localhost:58000/auth/google/callback`
   - 생성 후 `Client ID`, `Client secret` 보관

### 3) 애플리케이션 환경 변수(.env) 예시
다음은 예시 키이며, 실제 비밀값은 버전에 포함하지 말고 보안 저장에만 보관하세요.

```
GOOGLE_CLIENT_ID=xxxxxxxxxxxxxxxxxxxx.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=xxxxxxxxxxxxxxxxxxxxxxxx
GOOGLE_REDIRECT_URI=https://lunarsystem.co.kr/auth/google/callback
GOOGLE_OAUTH_SCOPES=openid email profile

# 로컬 개발 시 교체 예시
# GOOGLE_REDIRECT_URI=http://127.0.0.1:58001/auth/google/callback
# 또는(프런트 처리) http://localhost:58000/auth/google/callback
```

### 4) 구현 체크리스트(요약)
- 프런트엔드
  - **Google Identity Services** 버튼/원탭 또는 표준 OAuth 2.0 Authorization Code 흐름 사용
  - 리디렉션 시 `state` 값 설정/검증(CSRF 방지)
  - BE 콜백 사용 시, 로그인 성공 후 FE로 세션 상태 반영(예: 쿠키 기반 세션)
- 백엔드
  - Authorization Code → Token 교환(토큰 엔드포인트)
  - **ID Token 검증**: `aud`(Client ID), `iss`(accounts.google.com), 만료 등
  - `email_verified` 확인, 신규 사용자는 가입 처리, 기존 사용자는 로그인 처리
  - 세션/쿠키 설정: `SameSite=None; Secure`(HTTPS 운영 기준), 로컬 개발시 설정 분기
  - 에러/취소 플로우 처리(사용자 취소, 만료, 중복 state 등)

필수 스코프
- `openid`, `email`, `profile` (최소 권한 원칙)

### 5) 테스트 시나리오
- 정상 플로우: Google 동의 → 콜백 → 신규 가입 → 로그인 유지
- 기존 사용자: Google 동의 후 기존 계정과 매칭 → 로그인
- 취소/오류: 취소 시 적절한 안내, 토큰 검증 실패 시 재시도/문의 유도
- CORS/쿠키: 로컬·운영 양쪽 모두 세션 정상 유지 확인

### 6) 운영 전 체크리스트
- 도메인 검증 완료(`lunarsystem.co.kr`)
- HTTPS 인증서 적용
- 개인정보처리방침/이용약관 공개 URL 정상 노출
- OAuth 동의화면 “프로덕션” 게시 및 검수 통과(필요 시)
- Authorized origins/redirect URIs 최종 도메인으로 교체
- 오류 로깅/알림 설정

### 부록 A) robots.txt 예시
```
User-agent: *
Disallow:

Sitemap: https://lunarsystem.co.kr/sitemap.xml
```

### 부록 B) 도메인 소유권 검증
- **DNS TXT**(권장): DNS에 제공된 TXT 레코드 추가 후 검증
- HTML 파일 업로드(대안): 루트에 검증용 HTML 파일 배포
- 메타 태그(대안): `<meta name="google-site-verification" content="...">` 삽입

주의
- 구글 이메일(SMTP/IMAP) 연동은 본 문서 범위에 포함하지 않습니다. 메일은 현행 lunarsystem.co.kr(Worksmobile)로 유지합니다.



## UniScan 전체 구조 개요

### 목표
- FE, BE, Agent 전 구성요소의 데이터 흐름과 역할을 한눈에 파악하도록 정리
- 개발 시 참조 문서로 사용(클래스/엔드포인트/메시지 스펙 포함)

### DB
- 몽고db 사용

---

## 구성요소와 책임

### FE (Flutter)
- 스캔/촬영 UI와 이벤트 처리
- 경량 서비스 `ScanService`로 모드 관리/이벤트 전파
- 캐싱 관리/통계 조회는 `EnhancedScanService`로 위임

핵심 클래스/파일
- `lib/screens/scan_screen.dart`: 단일 카메라 뷰 + 하단 탭/상태영역
- `lib/services/scan_service.dart`: onDetect 바인딩, 자동/수동, 이벤트 스트림
- `lib/services/enhanced_scan_service.dart`: 스캔 아이템 큐, 중복필터, 통계
- `lib/models/scan_item.dart`: `IScanItem`, `BarcodeScanItem`, `ImageScanItem`

주요 흐름
1) MobileScanner.onDetect → `ScanService.onBarcodeDetected`
2) (Auto ON) 즉시 처리, (Auto OFF) 대기 후 수동 처리
3) `EnhancedScanService.addBarcode`/`addImagePlaceholder`로 큐에 적재
4) 화면은 `scanItems`/스트림으로 실시간 반영

### BE (.NET 8 / ASP.NET Core)
- 스캔 아이템 수신/저장/브로드캐스트
- SignalR Hub로 클라이언트/에이전트에 이벤트 배포

핵심 파일
- `LnUniScannerBE/Controllers/ScannerController.cs`
- `LnUniScannerBE/Hubs/ScannerHub.cs`
- 설정: `appsettings.json`, `appsettings.Development.json`

타입별 처리 원칙
- 이미지: `/files/images/{userId}/{yyyyMMdd}/{yyyyMMdd-HHmmss_rand}.jpg` 저장 후 DB 기록
- 바코드: DB 기록 → ON 상태 에이전트로 WS 전송 → ACK 수신 시 DB 갱신

### UniScanAgent (Windows, .NET Framework 4.x)
- 전역 키보드/마우스 후킹
- BE로부터 바코드 수신 시 키보드 입력 시퀀스로 전송하여 스캐너 효과
- 효과음/토스트(온/오프), 트레이 아이콘, 서비스로 동작, Inno Setup 배포

---

## 인증/식별 설계 (게스트 모드 포함)

### 게스트 모드 기본 원칙
- 앱 최초 실행 시 BE에서 게스트 ID를 발급 받아 기기에 저장 후 즉시 로그인 상태로 동작
- 형식: 대문자 3자리 + 숫자 6자리 (정규식: `^[A-Z]{3}[0-9]{6}$`)
- 발급 시 서버가 토큰(GuestToken)을 함께 반환 → FE는 보안저장소에 저장하여 요청 시 첨부
- 이후 정식 회원가입 시 `Users` 테이블에 정식 Insert 및 기존 게스트 ID와 매핑

### FE 저장소 키 권장
- `uniscan.userId` (게스트ID 또는 정식 ID)
- `uniscan.isGuest` (true/false)
- `uniscan.token` (GuestToken 또는 AccessToken)
- `uniscan.issuedAt` (ISO8601)

### BE 엔드포인트 (Auth)
- POST `/api/auth/guest` (게스트 발급)
  - Request: `{ deviceId?: string }`
  - Response:
  {
    "userId": "ABC123456",
    "isGuest": true,
    "token": "guest.jwt.token",
    "issuedAt": "2025-09-25T12:00:00Z"
  }
- POST `/api/auth/signup` (게스트 → 정식 전환)
  - Request:
  {
    "guestId": "ABC123456",
    "email": "user@example.com",
    "password": "******",
    "displayName": "User"
  }
  - Response:
  {
    "userId": "U-20250925-0001",
    "isGuest": false,
    "token": "access.jwt.token"
  }

### Settings 탭 상단 카드 (FE)
- 항목: 현재 로그인 ID(게스트면 게스트번호) 항상 표시
- 우측: "PC SCAN" 버튼 → 에이전트 QR 스캔 워크플로우 진입
  - 스캔 성공 시: `POST /api/agents/bindByQr` 호출로 사용자-에이전트 바인딩
  - 실패/만료: 에러 토스트 및 재시도 유도

## 비기능 요구사항(NFR)
- 성능: 단말 1대 기준 초당 10건 바코드 처리(피크 50건/5초) 무손실 큐잉
- 확장성: 에이전트 최대 1,000대, 동시 접속 2,000 커넥션 처리 가능(Hub 스케일아웃 가정)
- 신뢰성: 업로드/전송 재시도(지수 백오프), 중복 방지(클라이언트/서버 모두)
- 보안: HTTPS, JWT/OAuth2, 에이전트 등록 토큰, 역할 기반 접근(사용자/에이전트/관리자)
- 관찰성: 구조화 로그, 요청/메시지 추적 ID, 핵심 지표(MQ 길이, 실패율), 경보

---

## FE 상세 설계

### ScanService (경량 이벤트 계층)
- 상태: `ScanMode`, `isAutoMode`, 최근 결과(바코드/이미지), 대기 바코드(pending)
- 스트림: `barcodeStream`, `imageStream`
- 동작:
  - onDetect(BarcodeCapture) → 중복 방지(2초) → Auto ON: 즉시 처리 / Auto OFF: pending 저장
  - captureImage() → 이미지 식별자 생성 → 이벤트 발행
- 예외/에러: onDetect 중 예외 무시(로그만), UI는 마지막 정상 상태 유지

### EnhancedScanService (큐/통계/중복필터)
- 데이터: `List<IScanItem>` 메모리 큐, 중복필터 맵(바코드→마지막 시간)
- 공개 API: `addBarcode`, `addImagePlaceholder`, `scanItems`, `getItemsCountByStatus`, `getProgressSummary`, 중복필터 설정/초기화
- 용량/수명 정책(권고):
  - 최대 아이템 5,000건(설정 가능). 초과 시 오래된 `completed/failed`부터 제거, 그 외 FIFO
  - 이미지 placeholder는 실제 파일 저장 전까지 메모리 참조만 유지
- 업로드 오케스트레이션(차후):
  - 전용 `UploadCoordinator`(별도 서비스)로 분리, Isolate/Timer 기반 처리
  - 상태: `cached→uploading→processing→completed/failed`
  - 재시도: 네트워크 오류 시 1s, 2s, 5s, 10s 백오프 최대 5회

### FE 에러 처리/UX
- 업로드 실패: 상태 패널에 실패 카운터, 항목 Detail에서 재시도 버튼 제공
- 네트워크 끊김: 상단 토스트/아이콘 표시, 자동 재시도 진행
- 저장소 부족(이미지): 파일 저장 실패 시 사용자 경고 및 자동 캐시 정리 유도

---

## BE 상세 설계

### REST API (초안)
- POST `/api/scanner/scan` (바코드/텍스트)
  - Request(JSON)
  {
    "data": "BARCODE_OR_TEXT",
    "type": "barcode",
    "userId": "string",
    "deviceId": "string",
    "options": { "sendEnter": true, "delayMs": 10 }
  }
  - Response(JSON)
  { "id": "guid", "status": "Success", "timestamp": "iso8601" }

- POST `/api/scanner/image` (이미지 업로드)
  - multipart/form-data: `file`(binary), `userId`, `deviceId`, `fileName`(optional)
  - 저장 후 DB 기록, `ScanItem` 생성, `ImageMedia` 메타 저장

- GET `/api/agents` / PATCH `/api/agents/{id}`
  - 목록 조회, 상태(ON/OFF), 그룹/권한 변경

- POST `/api/auth/guest`
  - 게스트 ID 발급(대문자3+숫자6) 및 GuestToken 반환

- POST `/api/auth/signup`
  - 게스트를 정식 사용자로 승격하고 AccessToken 발급

- GET `/api/scans` (필터: type, status, date range, userId)
  - 페이지네이션, 정렬

### SignalR Hub `/scannerhub`
- 그룹: `user:{userId}`, `agent:{agentId}`
- 서버→클라이언트 이벤트
  - `ScanResult` (FE/Agent 공통)
  - `AgentListUpdated` (관리 화면용)
  - `DispatchRequest` (Agent 대상 전송)
- 클라이언트→서버 메서드
  - `JoinGroup(group)`, `LeaveGroup(group)`
  - `AckDispatch({ id, agentId, success, error })`

### DB 스키마(초안, RDB)
- `Users`(UserId PK, Name, Role, ...)
- `Agents`(AgentId PK, Name, Status, LastSeenAt, Capabilities, OwnerUserId)
- `ScanItems`(ScanItemId PK, Type, Data, UserId, DeviceId, Status, Progress, CreatedAt, UpdatedAt)
- `ImageMedia`(MediaId PK, ScanItemId FK, FileName, FileSize, MimeType, StoragePath, Hash, CreatedAt)
- `ScanDispatches`(DispatchId PK, ScanItemId FK, AgentId FK, Status, SentAt, AckAt, Error)

DDL 예시(SQL)
```sql
CREATE TABLE ScanItems (
  ScanItemId UNIQUEIDENTIFIER PRIMARY KEY,
  Type VARCHAR(16) NOT NULL, -- barcode | image
  Data NVARCHAR(1024) NULL,  -- barcode text or description
  UserId NVARCHAR(64) NULL,
  DeviceId NVARCHAR(64) NULL,
  Status VARCHAR(16) NOT NULL, -- cached/uploading/processing/completed/failed
  Progress DECIMAL(5,2) NOT NULL DEFAULT 0,
  CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME(),
  UpdatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE ImageMedia (
  MediaId UNIQUEIDENTIFIER PRIMARY KEY,
  ScanItemId UNIQUEIDENTIFIER NOT NULL REFERENCES ScanItems(ScanItemId),
  FileName NVARCHAR(260) NOT NULL,
  FileSize BIGINT NOT NULL,
  MimeType VARCHAR(64) NOT NULL,
  StoragePath NVARCHAR(400) NOT NULL,
  Hash VARBINARY(32) NULL,
  CreatedAt DATETIME2 NOT NULL DEFAULT SYSUTCDATETIME()
);

CREATE TABLE Agents (
  AgentId UNIQUEIDENTIFIER PRIMARY KEY,
  Name NVARCHAR(128) NOT NULL,
  Status VARCHAR(16) NOT NULL, -- online/offline/disabled
  LastSeenAt DATETIME2 NULL,
  Capabilities NVARCHAR(256) NULL,
  OwnerUserId NVARCHAR(64) NULL
);

CREATE TABLE ScanDispatches (
  DispatchId UNIQUEIDENTIFIER PRIMARY KEY,
  ScanItemId UNIQUEIDENTIFIER NOT NULL REFERENCES ScanItems(ScanItemId),
  AgentId UNIQUEIDENTIFIER NOT NULL REFERENCES Agents(AgentId),
  Status VARCHAR(16) NOT NULL, -- pending/sent/acked/failed
  SentAt DATETIME2 NULL,
  AckAt DATETIME2 NULL,
  Error NVARCHAR(400) NULL
);
```

### 저장소/경로 정책(이미지)
- 루트: `{BE}/files/images/{userId}/{yyyyMMdd}/{yyyyMMdd-HHmmssfff}_{rand}.jpg`
- 파일명 충돌 방지: 타임스탬프+난수+해시 일부
- 보존: 기본 180일(환경 변수), 주기적 정리 배치
- 백업/안티바이러스 예외 경로 문서화

### 보안 설계
- 인증: JWT(Bearer), 에이전트 등록 시 일회성 Enrollment Token 발급 → 영구 Agent Token 교체
- 권한: 사용자/에이전트/관리자 Role, 엔드포인트/Hub 메서드별 정책
- 전송 보안: HTTPS 강제, HSTS, CORS(127.0.0.1:58000 허용)
- 입력 검증: 이미지 MIME/확장자 화이트리스트, 사이즈 제한, 바코드 길이 제한

### 관찰성/로깅
- BE: 구조화 로그(요청ID, 사용자, 스캔ID, 디스패치ID), 요청-응답 ms, 실패 사유
- Hub: 연결 수, 그룹별 메시지 수, 실패율, 재시도 횟수
- 지표: 업로드 대기 큐 길이, 에이전트 온라인 수, 일일 처리량

### 배포/환경
- Dev: `dotnet run`; Swagger 개발 모드 / CORS 로컬 허용
- Prod: Kestrel+Nginx(리버스 프록시), 로그 롤링, 파일 스토리지 퍼미션
- 설정: 저장 루트, CORS Origin, JWT 서명키, Hub 경로(`/scannerhub`)

---

## Agent 상세 설계

### 아키텍처
- Windows Service(백그라운드) + Tray UI(사용자 인터랙션)
- 상호 통신: Named Pipe 또는 gRPC over NamedPipe(권고: Named Pipe)

### 동작 플로우
1) 서비스가 Hub(`/scannerhub`)에 `agent:{agentId}` 그룹으로 접속
2) `DispatchRequest` 수신 시 데이터 파싱 → 키 입력 시퀀스 생성
3) 옵션(sendEnter, delayMs) 반영하여 `SendInput` 호출 시뮬레이션
4) 성공/실패를 `AckDispatch`로 서버에 회신, Tray에 토스트/사운드 표시

### 등록/바인딩 시나리오
- 설치 시 에이전트가 하드웨어 키로 등록 요청
  - 하드웨어 키: `SHA256( MachineName + '|' + PrimaryIPv4 + '|' + Salt )` → 16~32바이트 트렁케이션 저장
  - POST `/api/agents/register`
  {
    "hardwareKey": "ab12cd34...",
    "machineName": "DESKTOP-1234",
    "ip": "192.168.0.12"
  }
  - Response:
  {
    "agentId": "AG-20250925-0001",
    "qrToken": "short.lived.token",
    "expiresAt": "2025-09-25T12:10:00Z"
  }
- 에이전트는 QR 생성(표시)
  - QR 텍스트: `uniscan://agent/enroll?agentId=AG-2025...&token=...`
- FE Settings의 "PC SCAN"으로 스캔 → 바인딩 요청
  - POST `/api/agents/bindByQr`
  {
    "agentId": "AG-20250925-0001",
    "token": "short.lived.token",
    "userId": "ABC123456"  // 게스트 가능
  }
  - 성공 시: 에이전트에 사용자 바운드, Hub 그룹에 참여
- 대안: 에이전트 UI에서 사용자 ID(게스트번호 또는 정식ID) 직접 입력 후 바인딩
  - POST `/api/agents/bindManual` { agentId, userId }

### 설정/배포
- 설정 파일: `%ProgramData%/UniScanAgent/config.json`
  - { serverUrl, agentId, token, sendEnter, delayMs, soundOn, toastOn }
- 설치: Inno Setup, 서비스 등록(sc.exe) 및 자동 시작
- 업데이트: 수동/자동(차후), Crash 로그/덤프 수집

### 키 입력 시뮬레이션(.NET Framework 4.x)
- Win32 `SendInput`, `keybd_event` 래핑, Unicode 문자 처리, 포커스 창 검증
- 안전장치: 입력 길이 상한, 블랙리스트 창 제외, ESC로 정지 핫키

---

## 시퀀스(텍스트)

### 바코드(자동)
FE: onDetect → addBarcode → UI 업데이트
BE: (옵션) 업로드 API 호출 → ScanItem 저장 → 에이전트 Dispatch → ACK

### 이미지
FE: capture → (파일 저장 후) 업로드 → 저장/기록

---

## TODO 로드맵(세부)
- FE
  - 이미지 파일 저장/썸네일 생성 유틸 추가
  - UploadCoordinator 도입(비동기 업로드/재시도/상태 반영)
  - 결과 상세에 재시도/삭제/공유 액션
- BE
  - 이미지 업로드 엔드포인트, 저장/DB 연계 구현
  - Dispatch/ACK 트랜잭션 보장, 중복 전송 방지 키(ScanItemId+AgentId)
  - Agent 관리 API(등록/상태 변경/목록)
- Agent
  - Hub 클라이언트/재연결/백오프
  - 키 입력 시퀀스 안정화, 소리/토스트 설정
  - 설치/업데이트 파이프라인

## 인터페이스 정의(초안)

### FE → BE REST
- POST `/api/scanner/scan`
  - 요청
  ```json
  {
    "data": "BARCODE_OR_TEXT",
    "type": "barcode | image",
    "userId": "optional",
    "deviceId": "optional",
    "fileName": "optional for image",
    "fileUrl": "optional for image"
  }
  ```
  - 응답
  ```json
  {
    "id": "guid",
    "status": "Success | Error",
    "timestamp": "2025-09-12T12:34:56Z"
  }
  ```

### BE SignalR Hub `/scannerhub`
- 서버→클라: `ScanResult`
```json
{
  "id": "guid",
  "type": "barcode | image",
  "data": "text or fileName",
  "userId": "string",
  "timestamp": "iso8601",
  "status": "Queued | Sent | Acked | Error"
}
```
- 그룹 관리: `JoinGroup(group)`, `LeaveGroup(group)`
- 브로드캐스트: `SendScanResult(scanData)`

### BE ↔ Agent (WS 또는 SignalR 선택)
- 채널: Hub 그룹(에이전트별/사용자별)
- 메시지(바코드 전달)
```json
{
  "id": "guid",
  "type": "barcode",
  "data": "BARCODE_TEXT",
  "options": {
    "sendEnter": true,
    "delayMs": 10
  }
}
```
- ACK
```json
{ "id": "guid", "ack": true, "receivedAt": "iso8601" }
```

---

## 상태/데이터 모델

### FE IScanItem
```ts
interface IScanItem {
  id: string;
  type: 'barcode' | 'image';
  timestamp: string;
  status: 'cached' | 'uploading' | 'processing' | 'completed' | 'failed';
  progress: number; // 0..1
  displayText: string;
  thumbnailPath?: string;
  filePath?: string;
}
```

---

## TODO 로드맵(요약)
- FE: 실제 이미지 파일 저장/썸네일 생성 + 파일 캐시 관리
- FE: 업로드 진행률/재시도 전략, 실패 큐 분리
- BE: 이미지 저장 경로 구조/권한/정리 배치, DB 스키마
- BE: 에이전트 라우팅/ACK 트랜잭션, 전송 실패 재시도
- Agent: 키 입력 시퀀스 안정화, 효과음/토스트 설정, 업데이트 채널



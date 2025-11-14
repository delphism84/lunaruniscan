## UniScan FE/BE 기능 구성 문서

참고: 전체 구조/상세 설계는 `uniscan-structure.md`를 확인하세요.

### 주요 흐름 요약(요구사항 정리)
- Barcode 스캔 → 인식 이벤트 → 캐싱(바코드) 등록
- Camera 촬영 → 촬영 이벤트 → 캐싱(사진) 등록

### 코드1: 바코드 스캔 라이브러리 사용(현재 동작 + 계획)
- 사용 라이브러리: `mobile_scanner`
- 바코드: `MobileScanner.onDetect → ScanService.onBarcodeDetected → EnhancedScanService.addBarcode`
- 카메라: Camera 탭에서 촬영 버튼 → `ScanService.captureImage → EnhancedScanService.addImagePlaceholder`
  - 현 상태: 실제 파일 저장 없이 placeholder 등록
  - 계획: 실제 촬영 파일 저장(또는 선택) 후 캐싱 서비스에 파일 경로 전달

### 코드2: 캐싱 관리(현재 동작 + 계획)
- 현 상태(메모리 캐시):
  - `EnhancedScanService`가 `IScanItem` 목록(바코드/이미지)을 메모리에 유지
  - 중복 바코드 필터(기본 5초): 동일 바코드 연속 인식 방지, 설정/초기화 가능
- 계획(파일 캐시 + 업로드):
  - 캐싱 등록: 스캔 아이템을 파일로 생성/보관
    - type: `barcode | image`
    - content: 바코드 텍스트 또는 이미지 파일(`png/jpg`)
  - 캐싱 업로드: BE API로 전달하며 진행률 표시
    - 성공: 캐시 파일 삭제, 기록만 보존
    - 실패: 재시도/백오프, 실패 기록 유지

### UniScanAgent 관리(프런트엔드)
- BE에서 등록된 에이전트(PC 설치형) 목록 조회/표시
- 바코드 타입 처리 시, 사용자 선택(ON)된 에이전트로 전달될 수 있도록 라우팅 설정

### 백엔드 처리 원칙(타입별)
- 이미지 타입:
  - 저장 경로: `BE 실행 폴더/files/images/{userId}/{yyyyMMdd}/{yyyyMMdd-HHmmss_랜덤}.jpg`
  - DB 기록(메타: userId, 파일 경로, 업로드 시각, 상태)
  - 현 단계: 여기까지 구현 후 이후는 TODO로 남김
- 바코드 타입:
  - DB 기록(데이터, userId, 시각, 상태)
  - 에이전트 ON 상태인 대상에게 WS 세션으로 전송
  - 전송 완료 시 DB ack 갱신

### UniScanAgent(요구사항)
- C# .NET Framework 4.x
- 전역 후킹(키보드/마우스)
- BE에서 scanitem 수신 시 키보드 입력 신호로 내보내 바코드 스캐너 효과 제공
- 효과음 재생(Agent 내 ON/OFF), 좌측하단 자체 토스트(ON/OFF)
- Tray 아이콘, Inno Setup 설치, 서비스로 구동


### 목적
UniScan 시스템의 프런트엔드(Flutter)와 백엔드(.NET) 구성, 데이터 흐름, API/HUB 사양, 실행 방법을 한 문서에 정리한다.

## 프런트엔드(Flutter)

### 런타임/포트
- FE 개발 서버: http://127.0.0.1:58000 (사용자 선호 설정)
- 개발 서버 IP : 175.100.115.114

### 주요 의존성
- 카메라/바코드: mobile_scanner 플러그인 사용. 단일 위젯 기반 단순 구조로 구현됨. [모듈 문서](https://pub.dev/packages/mobile_scanner)

### 화면/UX 구성
- 단일 카메라 미리보기 레이아웃 상단(Expanded) 고정
- 하단 140px 컨트롤 영역을 2행으로 구성
  - 1행(70px): 상태 패널
    - 바코드 탭: 자동인식 토글, 상태/결과 영역, 우측 원형 카운터 뱃지(클릭 시 카운터 초기화)
    - 카메라 탭: 상태 텍스트(마지막 촬영 결과 표시), 촬영 버튼, 우측 원형 카운터 뱃지(클릭 시 카운터 초기화)
  - 2행(70px): 탭 메뉴
    - 좌: Barcode Scan
    - 우: Camera Scan

### 스캔/촬영 동작 모델
- 단일 MobileScanner 위젯으로 영상 스트림 표출
- 모드 전환은 하단 탭 클릭으로 수행(Barcode ↔ Camera)
- 모드에 따라 상태 패널만 바뀌며, 영상 레이아웃은 재사용
  - Barcode 모드
    - 자동(ON): 바코드 감지 시 즉시 처리
    - 수동(OFF): 바코드 감지 → 상태 패널에 "인식" 버튼 표시 → 버튼 누르면 처리
    - 최근 인식 결과를 녹색 라운드 뱃지로 표시, 하단에 HH:mm:ss 시간 표기
  - Camera 모드
    - 상태 패널에 촬영 버튼 노출(영상 위 오버레이 없음)
    - 버튼 클릭 시 촬영 이벤트를 결과로 발행(이미지 파일 저장은 책임 외)

### 상태 유지 정책
- 탭 전환 시 마지막 결과(바코드/이미지)를 상태 패널에 유지하여 재렌더링
- 영상은 항상 동일 레이아웃을 유지하므로, 카메라 시작/정지로 인한 오류(already started 등)를 회피

### ScanService (싱글톤)
- ScanMode: barcode | camera
- isAutoMode: 자동 인식 여부(Barcode 모드에서만 의미)
- Streams
  - barcodeStream: String (마지막 인식된 바코드 데이터 단위 이벤트)
  - imageStream: String (촬영 결과 식별자/경로 문자열 이벤트)
- 최근 결과 보관
  - lastBarcodeResult: String, lastBarcodeTime: DateTime?
  - lastImageResult: String, lastImageTime: DateTime?
- 카운터/큐
  - barcodeCount, imageCount, totalCount
  - 내부 resultQueue(List<ScanResult>) 및 3초 주기 목업 비동기 처리
    - ScanResult: { data, timestamp, type: 'barcode'|'image' }

#### ScanService 공개 API 요약
- setMode(ScanMode mode): 모드 전환(Barcode/Camera)
- setAutoMode(bool isAuto): 자동 인식 on/off
- onBarcodeDetected(BarcodeCapture capture): MobileScanner의 onDetect에 바인딩
- processManualBarcode(): 수동 모드에서 대기 중 바코드 처리
- captureImage(): Camera 모드에서 촬영 이벤트 발행(이미지 저장은 외부 책임)
- resetCounters(): 인식 카운터 초기화
- Streams: barcodeStream, imageStream

#### 데이터 흐름(Barcode / Auto ON)
1) MobileScanner.onDetect → ScanService.onBarcodeDetected 호출
2) 중복 필터(2초) 후 즉시 _processBarcodeResult
3) 최근 결과/시간 갱신, 카운터 +1, 큐에 추가, barcodeStream 이벤트 발행
4) 상태 패널 뱃지/시간/카운터 업데이트

#### 데이터 흐름(Barcode / Auto OFF)
1) onDetect 시 pendingBarcodeData에 저장 → 상태 패널에 "인식" 버튼 노출
2) 사용자가 인식 버튼 클릭 → processManualBarcode → _processBarcodeResult

#### 데이터 흐름(Camera)
1) 사용자가 촬영 버튼 클릭 → captureImage 호출
2) 최근 결과/시간 갱신, 카운터 +1, 큐에 추가, imageStream 이벤트 발행

#### 큐 처리(목업)
- 3초 주기 타이머로 큐에서 결과 1건씩 꺼내 로그 처리
- 실제 서버 전송/영구 저장은 추후 단계에서 구현(현 단계는 목업)

### 주의/제한
- 이미지 저장 경로/파일 I/O는 ScanService 책임에서 제외(상위 UI/캐싱 서비스에서 처리)
- SignalR 직접 연동은 아직 FE에 없고, 일반 WebSocket 서비스가 별도 제공됨(하단 참조)

### WebSocketService (일반 WS)
- web_socket_channel 기반의 경량 WebSocket 클라이언트
- 자동 재연결(최대 5회), 하트비트(30초), 방송형 메시지 송수신
- SignalR 프로토콜은 사용하지 않음(백엔드 ScannerHub와는 별개 경로)

## 백엔드(.NET 8 / ASP.NET Core)

### 런타임/포트
- HTTP: http://localhost:51111
- HTTPS: https://localhost:51112
- CORS 허용: http://127.0.0.1:58000, http://localhost:58000

### REST API
- Base: /api/scanner

1) GET /
   - 목적: 헬스체크
   - 응답: { message: "Scanner API is running", timestamp: DateTime }

2) POST /scan
   - 목적: 스캔 데이터 수신 및 브로드캐스트
   - 요청 바디:
```
{
  "data": "BARCODE_OR_TEXT",
  "deviceId": "optional",
  "userId": "optional"
}
```
   - 응답 바디:
```
{
  "id": "guid",
  "data": "BARCODE_OR_TEXT",
  "timestamp": "2025-09-12T12:34:56",
  "status": "Success"
}
```
   - 부가 동작: SignalR Hub를 통해 모든 클라이언트에 ScanResult 이벤트 발송

### SignalR Hub
- 경로: /scannerhub
- 그룹 관리: JoinGroup(group), LeaveGroup(group)
- 브로드캐스트: SendMessage(user, message), SendScanResult(scanData), SendToGroup(group, message)
- 연결 이벤트: UserConnected, UserDisconnected
- 서버→클라이언트 표준 이벤트(컨트롤러에서도 사용)
  - "ScanResult": { id, data, timestamp, status }

### 설정(appsettings.json)
- 로깅 레벨
- Kestrel Endpoints: 51111/51112 명시

## FE↔BE 통신 전략

### 현재
- FE는 카메라/바코드 스캔 로컬 처리 및 큐 목업 처리 중심
- BE는 REST(POST /scan) 및 SignalR 허브 제공(브로드캐스트/그룹)
- FE의 일반 WebSocketService는 범용 메시지 수신용(별도 서버/데모와 연결 가능)

### 차후 권장(선택)
- FE에 SignalR 클라이언트 도입하여 `/scannerhub` 직접 구독
- 스캔/촬영 결과 큐 처리 완료 시점에 BE에게 업링크(REST or Hub) → 서버 브로드캐스트 수신으로 FE간 동기화

## 개발/실행 방법

### 백엔드
1) 폴더: lnuniserverbe/LnUniScannerBE
2) 실행
```
dotnet restore
dotnet run
```
3) Swagger: 개발 모드에서 /swagger

### 프런트엔드
1) 폴더: lnuniscnnerfeapp/lnuniscnnerfeapp
2) 실행
```
flutter pub get
flutter run
```

## 권한/플랫폼 참고

### Android
- Camera 권한 필요(플러그인이 자동 처리하나, 매니페스트 확인 권장)
- CameraX/MLKit 번들/언번들 선택 가능 (패키지 문서 참고)

### iOS/macOS
- Info.plist: NSCameraUsageDescription(필수), NSPhotoLibraryUsageDescription(갤러리 사용 시)

### Web
- mobile_scanner 5.0.0+ 부터 스크립트 자동 로드(필수 스크립트 수동 추가 불필요)

참고: mobile_scanner 패키지 사용법 및 제약 사항은 공식 문서를 확인하십시오. [mobile_scanner on pub.dev](https://pub.dev/packages/mobile_scanner)

## 테스트 시나리오 체크리스트
- Barcode Scan/Auto ON: 바코드 감지 즉시 뱃지/시간/카운터 갱신
- Barcode Scan/Auto OFF: 바코드 감지 → 인식 버튼 표시 → 클릭 시 갱신
- Camera Scan: 촬영 버튼 클릭 → 결과/시간/카운터 갱신
- 탭 전환: 최근 결과 유지
- 카운터 뱃지 클릭: 카운터 0으로 초기화
- 큐 비동기 처리: 3초마다 1건 처리 로그 출력
- BE POST /scan: 정상 200 응답 및 Hub 브로드캐스트 발생

## 변경/확장 포인트
- 이미지 파일 저장/썸네일 생성 로직: 별도 캐싱 서비스로 분리 구현
- 큐 처리기: 실제 서버 업링크 및 재시도 전략 추가
- FE SignalR 클라이언트 연계: Hub 이벤트 바인딩으로 상태 동기화

---
문서 버전: 2025-09-12
작성 근거: 현재 리포지토리의 FE/BE 소스 코드 및 mobile_scanner 공식 문서 [mobile_scanner on pub.dev](https://pub.dev/packages/mobile_scanner)


#UNISCAN
-바코드,카메라 스캔을 통해 바코드,영수증,라벨 내용을 집계
-바코드의 경우 PC에 에이전트를 설치하고 키보드후킹으로 바코드스캐너처럼 코드입력을 보낼 수 있음
-PC에 설치된 프린터(바코드프린터,일반)에 인쇄를 보낼 수 있음
-관리 사이트를 통해 바코드에 대한 제품 관리, 재고 관리, 입고/출고/생산/사용/불량 액션 가능


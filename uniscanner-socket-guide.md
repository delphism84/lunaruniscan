## UniScanner WebSocket 사용 가이드 (FE)

- 접속 URL: `wss://server.lunarsystem.co.kr:44444/ws/sendReq`
- 프로토콜: JSON 텍스트 메시지
- 메시지 타입: `barcode` | `image`
- 응답: 서버는 처리 시마다 `"ok"` 텍스트를 회신
- 저장: `image` 타입은 서버의 `/public/files/` 아래에 파일 저장, 저장 경로는 추후 REST로 제공 예정

### 공통 필드
- `userId` (string)
- `deviceId` (string)
- `msgType` (string: `barcode` | `image`)
- `msg` (string) - barcode 텍스트 또는 이미지의 base64를 보낼 때 사용 가능
- `imageBase64` (string, optional) - 데이터 URI 또는 순수 base64. 존재 시 우선 사용
- `imageExt` (string, optional) - 파일 확장자: `jpg`/`png` 등. 미지정 시 `jpg`
- `ack` (number, optional) - 기본 0
- `rxTime` (ISO-8601, optional) - 미지정 시 서버 UTC 시간

### 메시지 예시

#### 1) 바코드 전송
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123",
  "ack": 0
}
```

#### 2) 이미지 전송 (base64)
- data URI 형태 또는 순수 base64 모두 허용합니다.
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "image",
  "imageBase64": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ...",
  "imageExt": "jpg",
  "ack": 0
}
```

### 연결 코드 스니펫

#### 브라우저 (원시 WebSocket)
```javascript
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq');

ws.onopen = () => {
  // 예: 바코드 메시지
  ws.send(JSON.stringify({
    userId: 'u1',
    deviceId: 'd1',
    msgType: 'barcode',
    msg: 'CODE128-ABC-123',
    ack: 0
  }));
};

ws.onmessage = (e) => {
  console.log('server:', e.data); // "ok"
};

ws.onerror = (e) => console.error('ws error', e);
ws.onclose = () => console.log('ws closed');
```

#### Node.js (ws)
```javascript
const WebSocket = require('ws');
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq');

ws.on('open', () => {
  ws.send(JSON.stringify({
    userId: 'u1',
    deviceId: 'd1',
    msgType: 'image',
    imageBase64: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA...',
    imageExt: 'png'
  }));
});

ws.on('message', (msg) => console.log('server:', msg.toString()));
ws.on('error', console.error);
ws.on('close', () => console.log('ws closed'));
```

### 저장 및 접근
- 서버 저장 경로: `/var/uniscanner/docker/be/public/files/`
- 정적 제공 경로: `/public/files/<파일명>`
  - 예: `https://server.lunarsystem.co.kr/public/files/20250101_120000_123_u1_d1.jpg`

### 주의 사항
- 이미지 데이터가 큰 경우, 조각(fragment)으로 전송되어도 서버가 조립 후 처리합니다.
- `imageBase64`가 `data:` URI인 경우 서버가 접두어를 제거합니다.
- 파일명은 `UTC_타임스탬프_user_device.ext` 형식으로 저장됩니다.
- WSS는 Nginx를 통해 `44444` 포트로 노출되며, 내부 BE는 `45444`에서 동작합니다.

---

### 전체 샘플(JSON) - 키 포함

#### 1) 바코드 전송 전체 플로우
- 토큰 발급 요청(JSON)
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- 토큰 발급 응답(JSON)
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```
- WSS 접속 URL
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>
```
- 바코드 메시지(JSON)
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123",
  "ack": 0,
  "rxTime": "2025-09-13T09:00:00Z"
}
```

#### 2) 아주 작은(2px x 2px) 이미지 전송 전체 플로우
- 토큰 발급 요청(JSON)
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- 토큰 발급 응답(JSON)
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```
- WSS 접속 URL
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>
```
- 2x2 PNG 이미지 메시지(JSON)
```json
{
  "userId": "u1",
  "deviceId": "d1",
  "msgType": "image",
  "imageExt": "png",
  "imageBase64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0kAAAAFklEQVQImWNgoBpgYGBg+M+ABQwMAADpNQfL9nEo6QAAAABJRU5ErkJggg==",
  "ack": 0,
  "rxTime": "2025-09-13T09:00:00Z"
}
```

---

### 토큰 발급 및 인증 절차
- 기본 API Key: `lunar-earth-sun`
- 토큰 TTL: 120분 (환경변수 `TOKEN_TTL_MINUTES`로 조정 가능)
- 흐름: FE가 API 키로 토큰 발급 → WSS 접속 시 `?token=...` 쿼리로 전송 → BE가 만료/중복 세션 검사 및 접속 허용

#### 1) 토큰 발급 (REST)
- URL: `http://127.0.0.1:45444/api/token` (외부 노출 시 Nginx 프록시 구성 필요)
- 요청(JSON):
```json
{
  "apiKey": "lunar-earth-sun",
  "userId": "u1",
  "deviceId": "d1"
}
```
- 응답(JSON):
```json
{
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T08:06:22.044Z"
}
```

#### 2) WSS 접속 (토큰 포함)
- URL: `wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=<signed-token>`
- 중복 연결 방지: 같은 토큰으로 동시 접속 시 409 응답(토큰 사용 중)
- 만료/서명 오류: 401 응답
  - 주의: `token` 값은 `/api/token` 응답의 `token`을 사용합니다. `API_KEY_DEFAULT`나 `API_KEY_MASTER_B64`(Base64) 자체를 넣으면 401이 발생합니다.

#### 예제 (브라우저)
```javascript
// 1) 토큰 발급
const tokenResp = await fetch('https://server.lunarsystem.co.kr/api/token', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ apiKey: 'lunar-earth-sun', userId: 'u1', deviceId: 'd1' })
}).then(r => r.json());

// 2) 토큰으로 WSS 연결
const ws = new WebSocket(`wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=${encodeURIComponent(tokenResp.token)}`);
ws.onopen = () => {
  ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'barcode', msg: 'CODE128-ABC-123' }));
};
ws.onmessage = (e) => console.log('server:', e.data);
```

#### 예제 (Node.js)
```javascript
const fetch = require('node-fetch');
const WebSocket = require('ws');

(async () => {
  const tokenResp = await fetch('http://127.0.0.1:45444/api/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ apiKey: 'lunar-earth-sun', userId: 'u1', deviceId: 'd1' })
  }).then(r => r.json());

  const ws = new WebSocket(`wss://server.lunarsystem.co.kr:44444/ws/sendReq?token=${encodeURIComponent(tokenResp.token)}`);
  ws.on('open', () => ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'image', imageBase64: 'data:image/png;base64,...', imageExt: 'png' })));
  ws.on('message', (m) => console.log('server:', m.toString()));
})();
```

#### 운영 팁
- 토큰은 HMAC-SHA256으로 서명된 사용자/디바이스/만료 정보를 포함합니다.
- 백엔드는 토큰 만료 시 접속 거부, 세션 종료 시 토큰 제거로 간단히 관리합니다.
- 필요 시 토큰 TTL/비밀키(`API_KEY_DEFAULT`)를 환경변수로 교체하여 회전(rotate) 전략을 적용하세요.

### 키 우선순위와 환경변수
- 마스터 키(Base64) 우선: `API_KEY_MASTER_B64`가 설정되어 있으면 이를 디코딩해 서명 키로 사용합니다.
- 그 외에는 기본 키 문자열(`API_KEY_DEFAULT`, 기본값: `lunar-earth-sun`)을 사용합니다.
- 현재 운영 기본값
  - `API_KEY_MASTER_B64`: `bHVuYXItZWFydGgtc3Vu` ("lunar-earth-sun"의 Base64)
  - `API_KEY_DEFAULT`: `lunar-earth-sun`
  - `TOKEN_TTL_MINUTES`: `120`

발급 시 허용되는 apiKey 값
- 평문 `lunar-earth-sun` 또는 Base64 디코딩 결과 문자열(동일 값) 모두 허용됩니다.

### WSS-only 인증 (REST 없는 방식)
- 쿼리로 `apiKey`, `userId`, `deviceId`를 전달해 인증/세션을 수립합니다.
- URL 형식:
```
wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1
```
- 유효한 `apiKey`는 다음 중 하나와 일치해야 합니다:
  - `API_KEY_DEFAULT`의 평문 값 (`lunar-earth-sun`)
  - `API_KEY_MASTER_B64`를 Base64 디코딩한 문자열 (현재 동일 값)
- 세션/만료: 서버는 내부적으로 TTL(기본 120분)을 적용해 세션을 관리합니다. 동일 키+사용자+디바이스 조합 중복 접속 시 409가 발생할 수 있습니다.

#### 예제 (브라우저)
```javascript
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1');
ws.onopen = () => {
  ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'barcode', msg: 'CODE128-ABC-123' }));
};
ws.onmessage = (e) => console.log('server:', e.data);
```

#### 예제 (Node.js)
```javascript
const WebSocket = require('ws');
const ws = new WebSocket('wss://server.lunarsystem.co.kr:44444/ws/sendReq?apiKey=lunar-earth-sun&userId=u1&deviceId=d1');
ws.on('open', () => ws.send(JSON.stringify({ userId: 'u1', deviceId: 'd1', msgType: 'image', imageBase64: 'data:image/png;base64,...', imageExt: 'png' })));
ws.on('message', (m) => console.log('server:', m.toString()));
```

참고: 기존 토큰 방식은 대안으로 유지되며, `?token=<signed-token>`을 통해 동일 엔드포인트에 접속할 수 있습니다.

### WSS 로그인 플로우 (Flutter 포함)
- 접속: `wss://server.lunarsystem.co.kr:44444/ws/sendReq`
- 로그인 요청(JSON):
```json
{
  "msgType": "login",
  "userId": "admin",
  "password": "admin123",
  "deviceId": "d1"
}
```
- 로그인 성공 응답(JSON):
```json
{
  "type": "token",
  "token": "<signed-token>",
  "expiresAtUtc": "2025-09-13T10:00:00Z"
}
```
- 이후 모든 메시지에 `token` 필드를 포함해 전송합니다.
```json
{
  "userId": "admin",
  "deviceId": "d1",
  "token": "<signed-token>",
  "msgType": "barcode",
  "msg": "CODE128-ABC-123"
}
```

#### Flutter 예시 (web_socket_channel)
```dart
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';

final channel = WebSocketChannel.connect(
  Uri.parse('wss://server.lunarsystem.co.kr:44444/ws/sendReq'),
);

void loginAndSend() {
  channel.sink.add(jsonEncode({
    'msgType': 'login',
    'userId': 'admin',
    'password': 'admin123',
    'deviceId': 'd1',
  }));

  channel.stream.listen((event) {
    final msg = jsonDecode(event as String);
    if (msg['type'] == 'token') {
      final token = msg['token'];
      // send barcode
      channel.sink.add(jsonEncode({
        'userId': 'admin',
        'deviceId': 'd1',
        'token': token,
        'msgType': 'barcode',
        'msg': 'CODE128-ABC-123',
      }));
    }
  });
}
```

주의
- 현재 데모 자격(admin/admin123)은 환경변수 `AUTH_USER`, `AUTH_PASS`로 변경 가능합니다.
- 고정 키(apiKey) 기반 getToken 방식은 제거되었습니다. 반드시 `login` → `token` 수신 → `token` 포함 메시지 순으로 사용하세요.

보안 참고
- WSS(TLS)로 암호화되므로 전송 중 노출 위험은 낮습니다. 다만 클라이언트 단(브라우저/앱) 메모리를 리버싱해 토큰을 추출하는 행위는 TLS로 방어되지 않습니다.
- 완화책 권장: 짧은 TTL(예: 15~30분), 토큰 재발급 시 이전 토큰 즉시 폐기, 기기 바인딩(토큰 payload에 userId/deviceId 포함: 이미 구현), 서버측 레이트리밋/이상행위 탐지, 필요 시 메시지에 nonce/timestamp 추가 후 서버측 재사용 방지 검사.

### 바코드 이미지 인식 요청과 진행률 이벤트
- 요청(JSON): `msgType: "image"`, `taskType: "barcode"`, `token` 포함, base64 또는 gzip+base64 이미지 전송
```json
{
  "userId": "admin",
  "deviceId": "d1",
  "token": "<signed-token>",
  "msgType": "image",
  "taskType": "barcode",
  "imageExt": "png",
  "imageBase64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAYAAABytg0k...",
  "isGzip": false
}
```
- gzip(base64) 예시: `imageBase64`에 gzip으로 압축한 바이너리를 base64로 인코딩하여 넣고 `isGzip: true` 설정

- 서버가 보내는 진행 이벤트(JSON)
```json
{
  "type": "progress",
  "jobId": "c2a7...",
  "status": "uploading",
  "progress": 5,
  "etaSeconds": 5,
  "filePath": null,
  "error": null
}
```
- 상태 값: `uploading` → `processing` → `finish` (또는 `fail`)
- 주기: 상태 변경 시 또는 최소 1초마다 전송
- 완료 예시
```json
{
  "type": "progress",
  "jobId": "c2a7...",
  "status": "finish",
  "progress": 100,
  "etaSeconds": 0,
  "filePath": "/public/files/20250101_120000_123_admin_d1.png",
  "error": null
}
```

### DB 기록
- 컬렉션: `barcodeJobs`
- 필드: `jobId, userId, deviceId, status, progressPercent, etaSeconds, filePath, error, createdAt, updatedAt`

### 업로드 포맷
- 기본: `imageBase64` (data URI 가능)
- 압축: `isGzip: true`이면 gzip 해제 후 저장

### 비밀번호 재설정(WS)
1) 코드 발송
```json
{ "msgType": "emailSend", "email": "user@example.com" }
```
2) 코드 검증(선택적 확인)
```json
{ "msgType": "emailVerify", "email": "user@example.com", "code": "123456" }
```
3) 재설정
```json
{ "msgType": "passwordReset", "email": "user@example.com", "code": "123456", "password": "NewP@ss!" }
```
- 성공 응답: "password_reset_ok"
- 재설정 시 기존 세션은 모두 무효화됩니다.

### 구글 로그인 연동

- 지원 방식: 브라우저 OAuth 콜백 또는 `id_token` 직접 전달(WS)

#### 1) 브라우저 OAuth 콜백 플로우
- 시작 URL: `GET /auth/google/login`
  - 선택: `?returnTo=<URL>`을 state로 인코딩해 보존
- 콜백: `GET /auth/google/callback?code=...`
  - 응답(JSON):
```json
{ "token": "<signed-token>", "expiresAtUtc": "2025-09-13T10:00:00Z", "email": "user@example.com", "name": "User" }
```
- 받은 `token`을 이후 WSS 메시지의 `token` 필드에 포함하여 사용합니다.

환경변수
- `GOOGLE_CLIENT_IDS`: 허용 클라이언트 ID 목록(콤마 구분). 미지정 시 기본값 1개 사용
- `GOOGLE_CLIENT_ID`: 단일 클라이언트 ID (토큰 교환시 사용)
- `GOOGLE_CLIENT_SECRET`: 구글 OAuth 클라이언트 시크릿
- `GOOGLE_REDIRECT_URI`: 콜백 URL (예: `https://lunarsystem.co.kr/auth/google/callback`)
- `GOOGLE_CREDENTIALS_JSON_PATH`: 구글 자격파일(JSON) 경로. 지정 시 `client_secret`, `redirect_uris[0]` 자동 반영

설정 예시
```bash
# 시스템/도커 환경에 적용할 값 예시
export GOOGLE_CLIENT_IDS="257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com"
export GOOGLE_CLIENT_ID="257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="<YOUR_CLIENT_SECRET>"
export GOOGLE_REDIRECT_URI="https://lunarsystem.co.kr/auth/google/callback"
export GOOGLE_CREDENTIALS_JSON_PATH="/var/lunarsystem/client_secret_2_257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com.json"
```

Docker Compose 예시 (발췌)
```yaml
services:
  be:
    environment:
      - GOOGLE_CLIENT_IDS=257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com
      - GOOGLE_CLIENT_ID=257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com
      - GOOGLE_CLIENT_SECRET=${GOOGLE_CLIENT_SECRET}
      - GOOGLE_REDIRECT_URI=https://lunarsystem.co.kr/auth/google/callback
      - GOOGLE_CREDENTIALS_JSON_PATH=/var/lunarsystem/client_secret_2_257421771333-c03gmigm406vge3054qar0grokp7f78a.apps.googleusercontent.com.json
```

#### 2) `id_token` 직접 전달(WS)
- 클라이언트에서 구글 로그인 SDK로 `id_token`을 취득 후, 아래 메시지로 전송합니다.
```json
{
  "msgType": "googleLogin",
  "msg": "<google-id-token>",
  "deviceId": "d1"
}
```
- 성공 시 응답(JSON):
```json
{ "type": "token", "token": "<signed-token>", "expiresAtUtc": "2025-09-13T10:00:00Z" }
```
